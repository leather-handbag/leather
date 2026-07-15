-- Rate-limit verification attempts, sanitize public account DTOs and fix leaderboard aggregation.
alter table public.binding_challenges add column if not exists attempt_window_started_at timestamptz;
alter table public.binding_challenges add column if not exists window_attempts integer not null default 0 check(window_attempts between 0 and 10);
alter table public.binding_challenges add column if not exists last_attempt_at timestamptz;

create or replace function private.build_public_training_accounts(target_user uuid)
returns jsonb language sql stable security definer set search_path=public,pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object('platform',a.platform,'handle',a.handle,'avatar_url',a.avatar_url,'profile_url',a.profile_url,'status',a.status,'verified_at',a.verified_at,'last_success_at',a.last_success_at,'data_through',a.data_through) order by a.platform),'[]'::jsonb)
  from public.external_accounts a where a.user_id=target_user and a.status<>'disabled';
$$;

create or replace function public.get_training_profile(target_user uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_viewer uuid:=auth.uid();v_priv public.training_privacy;v_self boolean;v_profile record;v_model integer;
begin
  select * into v_priv from public.training_privacy where user_id=target_user;
  if not found then v_priv:=row(target_user,true,true,true,true,now())::public.training_privacy; end if;
  v_self:=v_viewer=target_user;
  select * into v_profile from public.public_profile_stats where id=target_user;
  if v_profile.id is null then return null; end if;
  select version into v_model from public.mastery_model_versions where active limit 1;
  return jsonb_build_object('generated_at',now(),'model_version',v_model,'user',jsonb_build_object('id',v_profile.id,'handle',v_profile.handle,'display_name',v_profile.display_name,'avatar_url',v_profile.avatar_url,'role',v_profile.role,'name_color',v_profile.name_color),
    'visibility',jsonb_build_object('accounts',v_self or v_priv.accounts_public,'heatmap',v_self or v_priv.heatmap_public,'map',v_self or v_priv.map_public,'recent',v_self or v_priv.recent_public),
    'accounts',case when v_self then private.build_training_accounts(target_user) when v_priv.accounts_public then private.build_public_training_accounts(target_user) else null end,
    'maps',case when v_self or v_priv.map_public then private.build_training_map(target_user) else null end,
    'summary',case when v_self or v_priv.map_public then jsonb_build_object('solved',(select count(*) from public.user_problem_progress where user_id=target_user and is_solved),'active_days',(select count(distinct activity_date) from public.training_daily_stats where user_id=target_user),'maps_unlocked',(select count(*) from public.map_unlocks where user_id=target_user)) else null end,
    'recent',case when v_self or v_priv.recent_public then coalesce((select jsonb_agg(x) from (select activity_date,sum(solved_count) solved,sum(submission_count) attempts from public.training_daily_stats where user_id=target_user group by activity_date order by activity_date desc limit 14) x),'[]'::jsonb) else null end);
end $$;

create or replace function public.get_explorer_leaderboard(limit_count integer default 100)
returns table(user_id uuid,handle text,display_name text,avatar_url text,role text,name_color text,maps_unlocked bigint,mastery_total bigint,last_unlocked_at timestamptz)
language sql stable security definer set search_path=public,pg_catalog
as $$
  select p.id,p.handle,p.display_name,p.avatar_url,p.role,p.name_color,coalesce(u.maps_unlocked,0),coalesce(s.mastery_total,0),u.last_unlocked_at
  from public.public_profile_stats p join public.training_privacy v on v.user_id=p.id and v.map_public
  left join lateral (select count(*) maps_unlocked,max(unlocked_at) last_unlocked_at from public.map_unlocks where user_id=p.id) u on true
  left join lateral (select coalesce(sum(sm.mastery_percent),0)::bigint mastery_total from public.skill_mastery sm join public.map_regions r on r.code=sm.region_code and r.is_core where sm.user_id=p.id and sm.model_version=(select version from public.mastery_model_versions where active limit 1)) s on true
  order by coalesce(u.maps_unlocked,0) desc,coalesce(s.mastery_total,0) desc,u.last_unlocked_at limit least(greatest(coalesce(limit_count,100),1),200);
$$;

grant execute on function public.get_training_profile(uuid),public.get_explorer_leaderboard(integer) to anon,authenticated;
revoke execute on function private.build_public_training_accounts(uuid) from public,anon,authenticated;
