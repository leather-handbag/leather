-- Harden game-map RPC grants and expose the rollout flag in the dashboard DTO.

revoke execute on function public.update_training_game_state(text,text,boolean,text),public.mark_unlock_event_seen(text),public.get_guardian_challenge(text),public.reroll_guardian_challenge(text) from public,anon;
revoke execute on function public.get_training_recommendations(integer) from public,anon;
grant execute on function public.update_training_game_state(text,text,boolean,text),public.mark_unlock_event_seen(text),public.get_guardian_challenge(text),public.reroll_guardian_challenge(text),public.get_training_recommendations(integer) to authenticated;

create or replace function public.update_training_game_state(
  selected_map_code text default null,selected_region_code text default null,
  audio_enabled_value boolean default null,effects_quality_value text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_user uuid:=auth.uid();v_region_map text;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if selected_map_code is not null and not exists(select 1 from public.map_unlocks where user_id=v_user and map_code=selected_map_code) then raise exception 'map is locked'; end if;
  if selected_region_code is not null then
    select map_code into v_region_map from public.map_regions where code=selected_region_code;
    if v_region_map is null then raise exception 'invalid region'; end if;
    if selected_map_code is not null and v_region_map<>selected_map_code then raise exception 'region does not belong to map'; end if;
    if not exists(select 1 from public.map_unlocks where user_id=v_user and map_code=v_region_map) then raise exception 'map is locked'; end if;
  end if;
  if effects_quality_value is not null and effects_quality_value not in ('auto','high','low') then raise exception 'invalid effects quality'; end if;
  insert into public.training_game_state(user_id,selected_map,selected_region,audio_enabled,effects_quality)
  values(v_user,selected_map_code,selected_region_code,coalesce(audio_enabled_value,false),coalesce(effects_quality_value,'auto'))
  on conflict(user_id) do update set selected_map=coalesce(excluded.selected_map,training_game_state.selected_map),selected_region=coalesce(excluded.selected_region,training_game_state.selected_region),audio_enabled=coalesce(audio_enabled_value,training_game_state.audio_enabled),effects_quality=coalesce(effects_quality_value,training_game_state.effects_quality),updated_at=now();
  return private.build_training_game_state(v_user);
end $$;

create or replace function public.get_my_training_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_catalog
as $$
declare v_user uuid:=auth.uid();v_result jsonb;v_model integer;v_scene jsonb;v_game jsonb;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select version into v_model from public.mastery_model_versions where active limit 1;
  v_scene:=private.build_training_game_scene(v_user,false);v_game:=private.build_training_game_state(v_user);
  select jsonb_build_object(
    'generated_at',now(),'data_through',(select max(data_through) from public.external_accounts where user_id=v_user and platform in ('codeforces','atcoder')),
    'model_version',v_model,'game_map_enabled',coalesce((select enabled from public.training_feature_flags where key='training_game_map_v1'),false),
    'classification_coverage',coalesce((select round(100.0*count(*) filter(where exists(select 1 from public.problem_skill_tags t where t.problem_id=p.problem_id and t.confidence>=.7))/nullif(count(*),0)) from public.user_problem_progress p where p.user_id=v_user and p.is_solved),0),
    'summary',jsonb_build_object('solved',(select count(*) from public.user_problem_progress where user_id=v_user and is_solved),'attempts',(select coalesce(sum(attempt_count),0) from public.user_problem_progress where user_id=v_user),'active_days',(select count(distinct activity_date) from public.training_daily_stats where user_id=v_user),'freshness',v_scene->'campfire_temperature','maps_unlocked',(select count(*) from public.map_unlocks where user_id=v_user)),
    'ability_estimate',private.build_ability_estimate(v_user),'accounts',private.build_training_accounts(v_user),'maps',private.build_training_map(v_user),
    'game_state',v_game,'scene_version',1,'node_states',v_scene->'node_states','path_states',v_scene->'path_states','campfire_temperature',v_scene->'campfire_temperature','map_star_summary',v_scene->'map_star_summary',
    'unseen_unlock_events',coalesce((select jsonb_agg(jsonb_build_object('event_id','map:'||u.map_code,'map_code',u.map_code,'unlocked_at',u.unlocked_at,'reason',u.detail->>'reason','detail',u.detail) order by u.unlocked_at) from public.map_unlocks u where u.user_id=v_user and not (v_game->'seen_unlock_event_ids' ? ('map:'||u.map_code))),'[]'::jsonb),
    'privacy',coalesce((select to_jsonb(p)-'user_id' from public.training_privacy p where p.user_id=v_user),'{}'::jsonb),
    'logs',coalesce((select jsonb_agg(x order by (x->>'created_at')::timestamptz desc) from (select jsonb_build_object('id',id,'type',type,'title',title,'message',message,'detail',detail,'created_at',created_at)x from public.expedition_logs where user_id=v_user order by created_at desc limit 20)q),'[]'::jsonb)
  ) into v_result;return v_result;
end $$;

revoke execute on function public.update_training_game_state(text,text,boolean,text) from public,anon;
grant execute on function public.update_training_game_state(text,text,boolean,text) to authenticated;
