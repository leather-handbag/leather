-- Secure daily/weekly catalog refresh claimed by the already scheduled worker.
create table if not exists public.training_catalog_state (
  platform text primary key check(platform in ('codeforces','atcoder')),
  interval_hours integer not null check(interval_hours between 1 and 720),
  status text not null default 'idle' check(status in ('idle','running','failed')),
  next_sync_at timestamptz not null default now(),
  locked_at timestamptz,
  last_success_at timestamptz,
  last_error text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.training_catalog_state(platform,interval_hours,next_sync_at) values('atcoder',24,now()),('codeforces',168,now()+interval '10 minutes')
on conflict(platform) do update set interval_hours=excluded.interval_hours;
alter table public.training_catalog_state enable row level security;
drop policy if exists training_catalog_state_client_deny on public.training_catalog_state;
create policy training_catalog_state_client_deny on public.training_catalog_state for all to anon,authenticated using(false) with check(false);
revoke all on public.training_catalog_state from public,anon,authenticated;

create or replace function public.claim_training_catalog_sync()
returns text language plpgsql security definer set search_path=public,pg_catalog
as $$
declare v_platform text;
begin
  update public.training_catalog_state set status='failed',locked_at=null,next_sync_at=now(),last_error='catalog worker lease expired',updated_at=now()
  where status='running' and locked_at<now()-interval '30 minutes';
  select platform into v_platform from public.training_catalog_state where status<>'running' and next_sync_at<=now() order by next_sync_at for update skip locked limit 1;
  if v_platform is null then return null; end if;
  update public.training_catalog_state set status='running',locked_at=now(),updated_at=now() where platform=v_platform;
  return v_platform;
end $$;

create or replace function public.finish_training_catalog_sync(platform_name text,succeeded boolean,error_message text default '')
returns void language plpgsql security definer set search_path=public,pg_catalog
as $$
begin
  update public.training_catalog_state set status=case when coalesce(succeeded,false) then 'idle' else 'failed' end,
    locked_at=null,last_success_at=case when coalesce(succeeded,false) then now() else last_success_at end,
    next_sync_at=case when coalesce(succeeded,false) then now()+make_interval(hours=>interval_hours) else now()+interval '1 hour' end,
    last_error=case when coalesce(succeeded,false) then '' else left(coalesce(error_message,'catalog refresh failed'),500) end,updated_at=now()
  where platform=platform_name;
end $$;

revoke execute on function public.claim_training_catalog_sync(),public.finish_training_catalog_sync(text,boolean,text) from public,anon,authenticated;
