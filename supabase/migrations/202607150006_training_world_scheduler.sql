-- Scheduled worker bootstrap and explicit deny policies for service-only ingestion tables.
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists private.training_worker_auth (
  singleton boolean primary key default true check(singleton),
  token_hash text not null,
  rotated_at timestamptz not null default now()
);
revoke all on private.training_worker_auth from public,anon,authenticated;

create or replace function public.verify_training_worker_token(provided_token text)
returns boolean language sql stable security definer set search_path=private,public,extensions,pg_catalog
as $$ select exists(select 1 from private.training_worker_auth where singleton and length(coalesce(provided_token,''))>=40 and crypt(provided_token,token_hash)=token_hash) $$;
revoke execute on function public.verify_training_worker_token(text) from public,anon,authenticated;

drop policy if exists submission_events_client_deny on public.submission_events;
create policy submission_events_client_deny on public.submission_events for all to anon,authenticated using(false) with check(false);
drop policy if exists training_sync_runs_client_deny on public.training_sync_runs;
create policy training_sync_runs_client_deny on public.training_sync_runs for all to anon,authenticated using(false) with check(false);

create or replace function public.configure_training_worker_schedule(project_url text,publishable_jwt text)
returns void language plpgsql security definer set search_path=public,private,vault,cron,net,extensions,pg_catalog
as $$
declare v_url text:=trim(trailing '/' from coalesce(project_url,''));v_key text:=trim(coalesce(publishable_jwt,''));v_worker_token text:=encode(gen_random_bytes(32),'hex');
begin
  if current_user not in ('postgres','service_role','supabase_admin') then raise exception 'service role required'; end if;
  if v_url !~ '^https://[a-z0-9-]+\.supabase\.co$' then raise exception 'invalid project URL'; end if;
  if length(v_key)<80 then raise exception 'a JWT-style publishable/anon key is required'; end if;
  insert into private.training_worker_auth(singleton,token_hash,rotated_at) values(true,crypt(v_worker_token,gen_salt('bf')),now())
  on conflict(singleton) do update set token_hash=excluded.token_hash,rotated_at=now();
  delete from vault.secrets where name in ('training_project_url','training_publishable_jwt','training_worker_token');
  perform vault.create_secret(v_url,'training_project_url','Leather training worker project URL');
  perform vault.create_secret(v_key,'training_publishable_jwt','Leather training worker gateway JWT');
  perform vault.create_secret(v_worker_token,'training_worker_token','Leather training worker request token');
  perform cron.schedule('leather-training-worker','*/5 * * * *',$job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name='training_project_url') || '/functions/v1/training-sync-worker',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='training_publishable_jwt'),
        'apikey',(select decrypted_secret from vault.decrypted_secrets where name='training_publishable_jwt'),
        'x-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='training_worker_token')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 10000
    );
  $job$);
  perform cron.schedule('leather-training-cron-cleanup','17 3 * * 0',$job$
    delete from cron.job_run_details where end_time < now()-interval '30 days';
  $job$);
end $$;

revoke execute on function public.configure_training_worker_schedule(text,text) from public,anon,authenticated;
comment on function public.configure_training_worker_schedule(text,text) is 'Service-only one-time bootstrap for the five-minute training Edge worker cron.';
