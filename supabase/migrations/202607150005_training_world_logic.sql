-- Leather Algorithm Expedition: aggregation, mastery, privacy-safe RPCs and worker queue.

create or replace function public.update_training_privacy(
  accounts_visible boolean,
  heatmap_visible boolean,
  map_visible boolean,
  recent_visible boolean
)
returns table(accounts_public boolean,heatmap_public boolean,map_public boolean,recent_public boolean,updated_at timestamptz)
language plpgsql security definer set search_path=public,pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  insert into public.training_privacy(user_id,accounts_public,heatmap_public,map_public,recent_public,updated_at)
  values(auth.uid(),coalesce(accounts_visible,true),coalesce(heatmap_visible,true),coalesce(map_visible,true),coalesce(recent_visible,true),now())
  on conflict(user_id) do update set accounts_public=excluded.accounts_public,heatmap_public=excluded.heatmap_public,
    map_public=excluded.map_public,recent_public=excluded.recent_public,updated_at=now();
  return query select p.accounts_public,p.heatmap_public,p.map_public,p.recent_public,p.updated_at
  from public.training_privacy p where p.user_id=auth.uid();
end $$;

create or replace function public.enqueue_training_sync(platform_name text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_user uuid:=auth.uid();v_account record;v_job uuid;v_jobs jsonb:='[]'::jsonb;v_existing record;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  if platform_name is not null and platform_name not in ('codeforces','atcoder','luogu') then raise exception 'invalid platform'; end if;
  for v_account in select * from public.external_accounts where user_id=v_user and status<>'disabled'
    and (platform_name is null or platform=platform_name) order by platform
  loop
    select id,status,created_at into v_existing from public.training_sync_jobs
    where external_account_id=v_account.id and status in ('queued','running') order by created_at desc limit 1;
    if v_existing.id is not null then
      v_jobs:=v_jobs||jsonb_build_array(jsonb_build_object('id',v_existing.id,'platform',v_account.platform,'status',v_existing.status,'cooldown',false));
      v_existing:=null;continue;
    end if;
    select id,status,created_at into v_existing from public.training_sync_jobs
    where external_account_id=v_account.id and requested_by='manual' and created_at>now()-interval '15 minutes'
    order by created_at desc limit 1;
    if v_existing.id is not null then
      v_jobs:=v_jobs||jsonb_build_array(jsonb_build_object('id',v_existing.id,'platform',v_account.platform,'status',v_existing.status,'cooldown',true));
      v_existing:=null;continue;
    end if;
    insert into public.training_sync_jobs(user_id,external_account_id,platform,kind,requested_by,priority)
    values(v_user,v_account.id,v_account.platform,case when v_account.last_success_at is null then 'initial' else 'incremental' end,'manual',50)
    returning id into v_job;
    v_jobs:=v_jobs||jsonb_build_array(jsonb_build_object('id',v_job,'platform',v_account.platform,'status','queued','cooldown',false));
  end loop;
  return jsonb_build_object('jobs',v_jobs,'queued_at',now());
end $$;

create or replace function public.claim_training_sync_job(worker_name text)
returns jsonb language plpgsql security definer set search_path=public,pg_catalog
as $$
declare v_job public.training_sync_jobs;
begin
  update public.training_sync_jobs set status='queued',locked_at=null,locked_by=null,
    run_after=now(),error_code='stale_lock',error_message='Worker lease expired'
  where status='running' and locked_at<now()-interval '10 minutes';
  select * into v_job from public.training_sync_jobs
  where status='queued' and run_after<=now() order by priority desc,created_at
  for update skip locked limit 1;
  if v_job.id is null then return null; end if;
  update public.training_sync_jobs set status='running',locked_at=now(),locked_by=left(coalesce(worker_name,'worker'),80),
    started_at=coalesce(started_at,now()),attempts=attempts+1 where id=v_job.id returning * into v_job;
  return to_jsonb(v_job);
end $$;

create or replace function public.acquire_training_platform_lease(platform_name text)
returns integer language plpgsql security definer set search_path=private,pg_catalog
as $$
declare v_wait integer;v_interval interval;
begin
  if platform_name not in ('codeforces','atcoder','luogu') then raise exception 'invalid platform'; end if;
  v_interval:=case platform_name when 'codeforces' then interval '2 seconds' when 'luogu' then interval '3 seconds' else interval '1 second' end;
  insert into private.platform_rate_leases(platform) values(platform_name) on conflict do nothing;
  select greatest(0,ceil(extract(epoch from (available_at-now()))*1000)::integer) into v_wait
  from private.platform_rate_leases where platform=platform_name for update;
  update private.platform_rate_leases set available_at=greatest(available_at,now())+v_interval,updated_at=now() where platform=platform_name;
  return coalesce(v_wait,0);
end $$;

create or replace function public.finish_training_sync_job(
  target_job uuid,
  outcome text,
  next_cursor jsonb default '{}'::jsonb,
  fetched_count integer default 0,
  inserted_count integer default 0,
  duration_ms integer default 0,
  failure_code text default '',
  failure_message text default '',
  more_pages boolean default false
)
returns void language plpgsql security definer set search_path=public,pg_catalog
as $$
declare v_job public.training_sync_jobs;v_delay interval;
begin
  select * into v_job from public.training_sync_jobs where id=target_job for update;
  if v_job.id is null then raise exception 'job not found'; end if;
  if outcome not in ('succeeded','partial','failed') then raise exception 'invalid outcome'; end if;
  insert into public.training_sync_runs(job_id,platform,outcome,fetched_count,inserted_count,duration_ms,error_code,error_message,details)
  values(v_job.id,v_job.platform,outcome,greatest(coalesce(fetched_count,0),0),greatest(coalesce(inserted_count,0),0),greatest(coalesce(duration_ms,0),0),left(coalesce(failure_code,''),80),left(coalesce(failure_message,''),500),jsonb_build_object('cursor',coalesce(next_cursor,'{}'::jsonb),'more_pages',coalesce(more_pages,false)));
  if outcome='failed' and v_job.attempts<v_job.max_attempts then
    v_delay:=case v_job.attempts when 1 then interval '30 seconds' when 2 then interval '2 minutes' when 3 then interval '10 minutes' when 4 then interval '1 hour' else interval '6 hours' end;
    update public.training_sync_jobs set status='queued',run_after=now()+v_delay+(random()*interval '20 seconds'),cursor=coalesce(next_cursor,cursor),
      locked_at=null,locked_by=null,error_code=left(coalesce(failure_code,''),80),error_message=left(coalesce(failure_message,''),500),processed_count=processed_count+greatest(coalesce(inserted_count,0),0) where id=v_job.id;
  elsif coalesce(more_pages,false) and outcome in ('succeeded','partial') then
    update public.training_sync_jobs set status='queued',run_after=now()+interval '2 seconds',cursor=coalesce(next_cursor,cursor),
      locked_at=null,locked_by=null,error_code=left(coalesce(failure_code,''),80),error_message=left(coalesce(failure_message,''),500),processed_count=processed_count+greatest(coalesce(inserted_count,0),0) where id=v_job.id;
  else
    update public.training_sync_jobs set status=outcome,cursor=coalesce(next_cursor,cursor),locked_at=null,locked_by=null,
      error_code=left(coalesce(failure_code,''),80),error_message=left(coalesce(failure_message,''),500),processed_count=processed_count+greatest(coalesce(inserted_count,0),0),finished_at=now() where id=v_job.id;
  end if;
end $$;

create or replace function private.refresh_training_aggregates(target_user uuid)
returns void language plpgsql security definer set search_path=public,pg_catalog
as $$
begin
  if target_user is null then return; end if;
  delete from public.user_problem_progress where user_id=target_user;
  insert into public.user_problem_progress(user_id,problem_id,platform,first_attempt_at,first_accepted_at,last_activity_at,attempt_count,failed_before_ac,is_solved)
  with grouped as (
    select e.problem_id,min(e.platform) platform,min(e.submitted_at) first_attempt_at,
      min(e.submitted_at) filter(where e.is_accepted) first_ac,max(e.submitted_at) last_activity_at,count(*) attempts
    from public.submission_events e where e.user_id=target_user group by e.problem_id
  )
  select target_user,g.problem_id,g.platform,g.first_attempt_at,g.first_ac,g.last_activity_at,g.attempts,
    (select count(*) from public.submission_events f where f.user_id=target_user and f.problem_id=g.problem_id and not f.is_accepted and (g.first_ac is null or f.submitted_at<g.first_ac)),g.first_ac is not null
  from grouped g;

  delete from public.training_daily_stats where user_id=target_user;
  insert into public.training_daily_stats(user_id,activity_date,platform,submission_count,accepted_submissions,solved_count)
  with events as (
    select (e.submitted_at at time zone 'Asia/Shanghai')::date activity_day,e.platform,count(*) submissions,count(*) filter(where e.is_accepted) accepts
    from public.submission_events e where e.user_id=target_user group by 1,2
  ),solves as (
    select (p.first_accepted_at at time zone 'Asia/Shanghai')::date activity_day,p.platform,count(*) solved
    from public.user_problem_progress p where p.user_id=target_user and p.is_solved group by 1,2
  )
  select target_user,e.activity_day,e.platform,e.submissions,e.accepts,coalesce(s.solved,0) from events e left join solves s using(activity_day,platform);
end $$;

create or replace function private.refresh_training_mastery(target_user uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_model integer;v_map record;v_prev text;v_unlocked uuid;v_bound integer;
begin
  if target_user is null then return; end if;
  select version into v_model from public.mastery_model_versions where active order by version desc limit 1;
  if v_model is null then return; end if;
  delete from public.skill_mastery where user_id=target_user and model_version=v_model;

  insert into public.skill_mastery(user_id,map_code,region_code,model_version,breadth_score,challenge_score,coverage_score,stability_score,mastery_percent,confidence,assessment,evidence,upper_evidence,solved_count,attempted_count,covered_skills,required_skills,active_days,active_weeks,last_trained_at,explanation)
  with solved_ranked as (
    select p.*,coalesce(a.canonical_problem_id,p.problem_id) canonical_id,
      row_number() over(partition by coalesce(a.canonical_problem_id,p.problem_id) order by p.first_accepted_at,p.problem_id) rn
    from public.user_problem_progress p left join public.problem_aliases a on a.problem_id=p.problem_id
    where p.user_id=target_user and p.is_solved
  ),solved as (select * from solved_ranked where rn=1),
  tag_counts as (select problem_id,count(*) cnt from public.problem_skill_tags where confidence>=0.7 group by problem_id),
  evidence_rows as (
    select s.problem_id,c.map_code,r.code region_code,t.skill_code,s.first_accepted_at,c.normalized_difficulty,
      t.confidence*(case
        when c.normalized_difficulty is null then 0
        when c.map_code='plains' and c.normalized_difficulty>=1000 then 1.15 when c.map_code='plains' and c.normalized_difficulty<900 then 0.85
        when c.map_code='bronze' and c.normalized_difficulty>=1300 then 1.15 when c.map_code='bronze' and c.normalized_difficulty<1200 then 0.85
        when c.map_code='silver' and c.normalized_difficulty>=1600 then 1.15 when c.map_code='silver' and c.normalized_difficulty<1500 then 0.85
        when c.map_code='gold' and c.normalized_difficulty>=1900 then 1.15 when c.map_code='gold' and c.normalized_difficulty<1800 then 0.85
        when c.map_code='platinum' and c.normalized_difficulty>=2267 then 1.15 when c.map_code='platinum' and c.normalized_difficulty<2133 then 0.85
        when c.map_code='master' and c.normalized_difficulty>=2667 then 1.15 when c.map_code='master' and c.normalized_difficulty<2533 then 0.85
        when c.map_code='legend' and c.normalized_difficulty>=3200 then 1.15 when c.map_code='legend' and c.normalized_difficulty<3000 then 0.85
        else 1 end)/sqrt(tc.cnt::numeric) credit,
      case when (c.map_code='plains' and c.normalized_difficulty>=1000) or (c.map_code='bronze' and c.normalized_difficulty>=1300) or
        (c.map_code='silver' and c.normalized_difficulty>=1600) or (c.map_code='gold' and c.normalized_difficulty>=1900) or
        (c.map_code='platinum' and c.normalized_difficulty>=2267) or (c.map_code='master' and c.normalized_difficulty>=2667) or
        (c.map_code='legend' and c.normalized_difficulty>=3200) then true else false end is_upper
    from solved s join public.problem_catalog c on c.id=s.problem_id and c.map_code is not null
    join public.problem_skill_tags t on t.problem_id=c.id and t.confidence>=0.7
    join tag_counts tc on tc.problem_id=c.id
    join public.map_region_skills rs on rs.skill_code=t.skill_code
    join public.map_regions r on r.code=rs.region_code and r.map_code=c.map_code
  ),agg as (
    select map_code,region_code,sum(credit) evidence,sum(credit) filter(where is_upper) upper_evidence,
      count(distinct problem_id) solved_count,count(distinct skill_code) covered_skills,
      count(distinct (first_accepted_at at time zone 'Asia/Shanghai')::date) active_days,
      count(distinct date_trunc('week',first_accepted_at at time zone 'Asia/Shanghai')) active_weeks,max(first_accepted_at) last_trained_at
    from evidence_rows group by map_code,region_code
  ),attempts as (
    select r.map_code,r.code region_code,count(distinct p.problem_id) attempted_count
    from public.user_problem_progress p join public.problem_catalog c on c.id=p.problem_id and c.map_code is not null
    join public.problem_skill_tags t on t.problem_id=c.id and t.confidence>=0.7
    join public.map_region_skills rs on rs.skill_code=t.skill_code join public.map_regions r on r.code=rs.region_code and r.map_code=c.map_code
    where p.user_id=target_user group by r.map_code,r.code
  ),required as (select region_code,count(*) filter(where required) required_skills from public.map_region_skills group by region_code),
  components as (
    select r.map_code,r.code region_code,r.breadth_target,r.upper_target,r.required_days,r.required_weeks,
      coalesce(a.evidence,0) evidence,coalesce(a.upper_evidence,0) upper_evidence,coalesce(a.solved_count,0) solved_count,
      coalesce(x.attempted_count,0) attempted_count,coalesce(a.covered_skills,0) covered_skills,coalesce(q.required_skills,0) required_skills,
      coalesce(a.active_days,0) active_days,coalesce(a.active_weeks,0) active_weeks,a.last_trained_at,
      least(1,coalesce(a.evidence,0)/r.breadth_target) breadth,
      least(1,coalesce(a.upper_evidence,0)/r.upper_target) challenge,
      case when coalesce(q.required_skills,0)=0 then 0 else least(1,coalesce(a.covered_skills,0)::numeric/q.required_skills) end coverage,
      .6*least(1,coalesce(a.active_days,0)::numeric/r.required_days)+.4*least(1,coalesce(a.active_weeks,0)::numeric/r.required_weeks) stability
    from public.map_regions r left join agg a on a.map_code=r.map_code and a.region_code=r.code
    left join attempts x on x.map_code=r.map_code and x.region_code=r.code left join required q on q.region_code=r.code
  ),scored as (
    select c.*,least(100,greatest(0,round(100*(.45*breadth+.25*challenge+.20*coverage+.10*stability))))::integer mastery
    from components c
  )
  select target_user,s.map_code,s.region_code,v_model,round(100*s.breadth,2),round(100*s.challenge,2),round(100*s.coverage,2),round(100*s.stability,2),s.mastery,
    case when s.evidence>=s.breadth_target*.7 and s.covered_skills>=greatest(1,ceil(s.required_skills*.6)) then 'high' when s.evidence>=3 and s.active_days>=2 then 'medium' else 'low' end,
    case when s.mastery>=80 and s.evidence>=s.breadth_target*.7 and s.upper_evidence>=2 then 'strength'
      when s.evidence<3 then 'unexplored' when s.mastery<=45 and s.attempted_count>=4 then 'weakness'
      when s.mastery>=60 and s.last_trained_at<now()-interval '180 days' then 'rusty' else 'steady' end,
    round(s.evidence,3),round(s.upper_evidence,3),s.solved_count,s.attempted_count,s.covered_skills,s.required_skills,s.active_days,s.active_weeks,s.last_trained_at,
    format('%s 道有效 AC，覆盖 %s/%s 子技能，上段证据 %s/%s；广度 %s%%、挑战 %s%%、覆盖 %s%%、稳定 %s%%。',s.solved_count,s.covered_skills,s.required_skills,round(s.upper_evidence,1),s.upper_target,round(100*s.breadth),round(100*s.challenge),round(100*s.coverage),round(100*s.stability))
  from scored s;

  insert into public.map_unlocks(user_id,map_code,model_version,detail) values(target_user,'plains',v_model,'{"reason":"starting_map"}'::jsonb) on conflict do nothing;
  v_prev:='plains';
  for v_map in select * from public.training_maps where position>1 order by position loop
    if exists(select 1 from public.map_unlocks where user_id=target_user and map_code=v_prev)
      and not exists(select 1 from public.map_regions r left join public.skill_mastery s on s.user_id=target_user and s.region_code=r.code and s.model_version=v_model where r.map_code=v_prev and r.is_core and coalesce(s.mastery_percent,0)<100)
    then
      v_unlocked:=null;
      insert into public.map_unlocks(user_id,map_code,model_version,detail) values(target_user,v_map.code,v_model,jsonb_build_object('reason','previous_map_mastered','previous',v_prev))
      on conflict do nothing returning target_user into v_unlocked;
      if v_unlocked is not null then
        insert into public.expedition_logs(user_id,type,title,message,detail) values(target_user,'map_unlocked','新地图已解锁：'||v_map.name,'所有核心板块已经点亮，通往'||v_map.name||'的传送门开启了。',jsonb_build_object('map',v_map.code));
      end if;
    end if;
    v_prev:=v_map.code;
  end loop;

  select count(*) into v_bound from public.external_accounts where user_id=target_user and status in ('active','degraded');
  if v_bound>=1 then perform private.award_achievement(target_user,'training_first_bind',v_bound||' 个平台'); end if;
  if v_bound>=3 then perform private.award_achievement(target_user,'training_three_platforms','三个平台'); end if;
  if exists(select 1 from public.training_maps m where not exists(select 1 from public.map_regions r left join public.skill_mastery s on s.user_id=target_user and s.region_code=r.code and s.model_version=v_model where r.map_code=m.code and r.is_core and coalesce(s.mastery_percent,0)<80)) then
    perform private.award_achievement(target_user,'training_balanced','核心板块均达到 80%');
  end if;
  if exists(select 1 from public.training_maps m where not exists(select 1 from public.map_regions r left join public.skill_mastery s on s.user_id=target_user and s.region_code=r.code and s.model_version=v_model where r.map_code=m.code and r.is_core and coalesce(s.mastery_percent,0)<100)) then
    perform private.award_achievement(target_user,'training_map_master','完整地图');
  end if;
end $$;

create or replace function private.refresh_training_recommendations(target_user uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_model integer;v_map text;v_region text;v_problem uuid;
begin
  select version into v_model from public.mastery_model_versions where active order by version desc limit 1;
  select m.code into v_map from public.map_unlocks u join public.training_maps m on m.code=u.map_code where u.user_id=target_user order by m.position desc limit 1;
  if v_map is null then v_map:='plains'; end if;
  delete from public.training_recommendations where user_id=target_user and recommendation_date=private.china_today();

  select s.region_code into v_region from public.skill_mastery s join public.map_regions r on r.code=s.region_code
  where s.user_id=target_user and s.model_version=v_model and s.assessment='weakness' order by s.mastery_percent,s.evidence desc limit 1;
  if v_region is null then select s.region_code into v_region from public.skill_mastery s join public.map_regions r on r.code=s.region_code where s.user_id=target_user and s.model_version=v_model and r.map_code=v_map and r.is_core order by s.mastery_percent,s.evidence limit 1; end if;
  select c.id into v_problem from public.problem_catalog c join public.problem_skill_tags t on t.problem_id=c.id and t.confidence>=0.7 join public.map_region_skills rs on rs.skill_code=t.skill_code
  where rs.region_code=v_region and c.is_available and not exists(select 1 from public.user_problem_progress p where p.user_id=target_user and p.problem_id=c.id and p.is_solved)
    and not exists(select 1 from public.training_recommendations old where old.user_id=target_user and old.problem_id=c.id and old.skipped_at>now()-interval '7 days')
  order by abs(coalesce(c.normalized_difficulty,0)-(select coalesce(avg(pc.normalized_difficulty),1000) from public.user_problem_progress up join public.problem_catalog pc on pc.id=up.problem_id where up.user_id=target_user and up.is_solved)),random() limit 1;
  if v_problem is not null then insert into public.training_recommendations(user_id,slot,problem_id,region_code,reason,score) values(target_user,'weakness',v_problem,v_region,'补齐可靠弱项，并增加该板块的有效证据。',1); end if;

  select s.region_code into v_region from public.skill_mastery s join public.map_regions r on r.code=s.region_code where s.user_id=target_user and s.model_version=v_model and r.map_code=v_map and r.is_core order by s.mastery_percent,s.evidence limit 1;
  select c.id into v_problem from public.problem_catalog c join public.problem_skill_tags t on t.problem_id=c.id and t.confidence>=0.7 join public.map_region_skills rs on rs.skill_code=t.skill_code
  where rs.region_code=v_region and c.map_code=v_map and c.is_available and not exists(select 1 from public.user_problem_progress p where p.user_id=target_user and p.problem_id=c.id and p.is_solved)
    and not exists(select 1 from public.training_recommendations n where n.user_id=target_user and n.recommendation_date=private.china_today() and n.problem_id=c.id)
  order by c.normalized_difficulty nulls last,random() limit 1;
  if v_problem is not null then insert into public.training_recommendations(user_id,slot,problem_id,region_code,reason,score) values(target_user,'progress',v_problem,v_region,'推进当前地图完成度，优先覆盖尚未点亮的核心板块。',.9); end if;

  select c.id into v_problem from public.problem_catalog c where c.map_code=v_map and c.is_available
    and not exists(select 1 from public.user_problem_progress p where p.user_id=target_user and p.problem_id=c.id and p.is_solved)
    and not exists(select 1 from public.training_recommendations n where n.user_id=target_user and n.recommendation_date=private.china_today() and n.problem_id=c.id)
  order by random() limit 1;
  if v_problem is not null then insert into public.training_recommendations(user_id,slot,problem_id,reason,score) values(target_user,'explore',v_problem,'探索一处随机遗迹，保持训练内容的新鲜感。',.5); end if;
end $$;

create or replace function public.refresh_training_user(target_user uuid)
returns void language plpgsql security definer set search_path=private,public,pg_catalog
as $$
begin
  if current_user not in ('postgres','service_role','supabase_admin') then raise exception 'service role required'; end if;
  perform private.refresh_training_aggregates(target_user);
  perform private.refresh_training_mastery(target_user);
  perform private.refresh_training_recommendations(target_user);
end $$;

create or replace function private.build_training_map(target_user uuid)
returns jsonb language sql stable security definer set search_path=public,pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object('code',m.code,'name',m.name,'subtitle',m.subtitle,'icon',m.icon,'position',m.position,'color',m.color,'description',m.description,
    'unlocked',u.map_code is not null,'unlocked_at',u.unlocked_at,
    'progress',coalesce((select round(avg(s.mastery_percent)) from public.map_regions r join public.skill_mastery s on s.region_code=r.code and s.user_id=target_user and s.model_version=(select version from public.mastery_model_versions where active limit 1) where r.map_code=m.code and r.is_core),0),
    'regions',coalesce((select jsonb_agg(jsonb_build_object('code',r.code,'name',r.name,'icon',r.icon,'description',r.description,'core',r.is_core,'percent',coalesce(s.mastery_percent,0),'confidence',coalesce(s.confidence,'low'),'assessment',coalesce(s.assessment,'unexplored'),'evidence',coalesce(s.evidence,0),'solved',coalesce(s.solved_count,0),'last_trained_at',s.last_trained_at,'explanation',coalesce(s.explanation,'尚无可靠训练证据。')) order by r.position) from public.map_regions r left join public.skill_mastery s on s.region_code=r.code and s.user_id=target_user and s.model_version=(select version from public.mastery_model_versions where active limit 1) where r.map_code=m.code),'[]'::jsonb)
  ) order by m.position),'[]'::jsonb)
  from public.training_maps m left join public.map_unlocks u on u.map_code=m.code and u.user_id=target_user;
$$;

create or replace function private.build_training_accounts(target_user uuid)
returns jsonb language sql stable security definer set search_path=public,pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'platform',a.platform,'handle',a.handle,'avatar_url',a.avatar_url,'profile_url',a.profile_url,'status',a.status,'verified_at',a.verified_at,'last_success_at',a.last_success_at,'data_through',a.data_through,'last_error',a.last_error_message) order by a.platform),'[]'::jsonb)
  from public.external_accounts a where a.user_id=target_user and a.status<>'disabled';
$$;

create or replace function private.build_public_training_accounts(target_user uuid)
returns jsonb language sql stable security definer set search_path=public,pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object('platform',a.platform,'handle',a.handle,'avatar_url',a.avatar_url,'profile_url',a.profile_url,'status',a.status,'verified_at',a.verified_at,'last_success_at',a.last_success_at,'data_through',a.data_through) order by a.platform),'[]'::jsonb)
  from public.external_accounts a where a.user_id=target_user and a.status<>'disabled';
$$;

create or replace function public.get_my_training_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public,private,pg_catalog
as $$
declare v_user uuid:=auth.uid();v_result jsonb;v_model integer;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select version into v_model from public.mastery_model_versions where active limit 1;
  select jsonb_build_object(
    'generated_at',now(),'data_through',(select max(data_through) from public.external_accounts where user_id=v_user),
    'model_version',v_model,'classification_coverage',coalesce((select round(100.0*count(*) filter(where exists(select 1 from public.problem_skill_tags t where t.problem_id=p.problem_id and t.confidence>=.7))/nullif(count(*),0)) from public.user_problem_progress p where p.user_id=v_user and p.is_solved),0),
    'summary',jsonb_build_object('solved',(select count(*) from public.user_problem_progress where user_id=v_user and is_solved),'attempts',(select coalesce(sum(attempt_count),0) from public.user_problem_progress where user_id=v_user),'active_days',(select count(distinct activity_date) from public.training_daily_stats where user_id=v_user),'freshness',coalesce((select least(100,round(100.0*count(distinct activity_date)/30)) from public.training_daily_stats where user_id=v_user and activity_date>=private.china_today()-89),0),'maps_unlocked',(select count(*) from public.map_unlocks where user_id=v_user)),
    'accounts',private.build_training_accounts(v_user),'maps',private.build_training_map(v_user),
    'privacy',coalesce((select to_jsonb(p)-'user_id' from public.training_privacy p where p.user_id=v_user),'{}'::jsonb),
    'logs',coalesce((select jsonb_agg(x order by (x->>'created_at')::timestamptz desc) from (select jsonb_build_object('type',type,'title',title,'message',message,'created_at',created_at) x from public.expedition_logs where user_id=v_user order by created_at desc limit 20) q),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;

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

create or replace function public.get_training_map(target_user uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_public boolean;begin
  select map_public into v_public from public.training_privacy where user_id=target_user;
  if auth.uid() is distinct from target_user and not coalesce(v_public,true) then return jsonb_build_object('locked',true,'maps',null); end if;
  return jsonb_build_object('locked',false,'maps',private.build_training_map(target_user),'generated_at',now(),'model_version',(select version from public.mastery_model_versions where active limit 1));
end $$;

create or replace function public.get_training_heatmap(target_user uuid,from_date date default null,to_date date default null,platform_name text default null)
returns table(activity_date date,platform text,submission_count bigint,accepted_submissions bigint,solved_count bigint)
language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_public boolean;v_viewer uuid:=auth.uid();v_staff boolean:=false;
begin
  if platform_name is not null and platform_name not in ('codeforces','atcoder','luogu') then raise exception 'invalid platform'; end if;
  select heatmap_public into v_public from public.training_privacy where user_id=target_user;
  if v_viewer is not null then v_staff:=private.is_staff(v_viewer); end if;
  if v_viewer is distinct from target_user and not coalesce(v_public,true) and not v_staff then raise exception 'training heatmap is private'; end if;
  if v_viewer is distinct from target_user and not coalesce(v_public,true) and v_staff then
    insert into private.training_access_audit(actor_id,target_user_id,resource,context) values(v_viewer,target_user,'private_heatmap',jsonb_build_object('from',from_date,'to',to_date,'platform',platform_name));
  end if;
  return query select d.activity_date,d.platform,sum(d.submission_count),sum(d.accepted_submissions),sum(d.solved_count)
  from public.training_daily_stats d where d.user_id=target_user and d.activity_date>=coalesce(from_date,private.china_today()-364) and d.activity_date<=coalesce(to_date,private.china_today()) and (platform_name is null or d.platform=platform_name)
  group by d.activity_date,d.platform order by d.activity_date,d.platform;
end $$;

create or replace function public.get_training_recommendations(limit_count integer default 3)
returns table(id uuid,slot text,reason text,score numeric,problem_id uuid,platform text,external_problem_id text,title text,url text,difficulty integer,map_code text,region_code text,skipped_at timestamptz,completed_at timestamptz)
language sql stable security definer set search_path=public,private,pg_catalog
as $$
  select r.id,r.slot,r.reason,r.score,c.id,c.platform,c.external_problem_id,c.title,c.url,c.normalized_difficulty,c.map_code,r.region_code,r.skipped_at,r.completed_at
  from public.training_recommendations r join public.problem_catalog c on c.id=r.problem_id where r.user_id=auth.uid() and r.recommendation_date=private.china_today()
  order by case r.slot when 'weakness' then 1 when 'progress' then 2 else 3 end limit least(greatest(coalesce(limit_count,3),1),10);
$$;

create or replace function public.skip_training_recommendation(recommendation_id uuid)
returns void language plpgsql security definer set search_path=public,pg_catalog
as $$ begin update public.training_recommendations set skipped_at=now() where id=recommendation_id and user_id=auth.uid(); end $$;

create or replace function public.get_training_sync_status()
returns jsonb language sql stable security definer set search_path=public,private,pg_catalog
as $$
  select jsonb_build_object('accounts',private.build_training_accounts(auth.uid()),'jobs',coalesce((select jsonb_agg(to_jsonb(j)-'user_id'-'locked_by' order by j.created_at desc) from (select * from public.training_sync_jobs where user_id=auth.uid() order by created_at desc limit 20) j),'[]'::jsonb));
$$;

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

create or replace function public.get_training_access_audit(target_user uuid,limit_count integer default 50)
returns table(actor_id uuid,actor_handle text,actor_name text,resource text,context jsonb,created_at timestamptz)
language plpgsql security definer set search_path=public,private,pg_catalog
as $$
begin
  if auth.uid() is distinct from target_user and not private.is_owner(auth.uid()) then raise exception 'permission denied'; end if;
  return query select a.actor_id,p.handle,p.display_name,a.resource,a.context,a.created_at from private.training_access_audit a join public.profiles p on p.id=a.actor_id where a.target_user_id=target_user order by a.created_at desc limit least(greatest(coalesce(limit_count,50),1),200);
end $$;

create or replace function public.get_training_admin_metrics()
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog
as $$
begin
  if not private.is_staff(auth.uid()) then raise exception 'permission denied'; end if;
  return jsonb_build_object(
    'generated_at',now(),
    'queue',jsonb_build_object('queued',(select count(*) from public.training_sync_jobs where status='queued'),'running',(select count(*) from public.training_sync_jobs where status='running'),'failed_24h',(select count(*) from public.training_sync_jobs where status='failed' and finished_at>now()-interval '24 hours')),
    'sources',coalesce((select jsonb_agg(x) from (select platform,status,count(*) accounts,max(last_success_at) last_success_at from public.external_accounts group by platform,status order by platform,status) x),'[]'::jsonb),
    'errors',coalesce((select jsonb_agg(x) from (select platform,error_code,count(*) occurrences,max(created_at) latest from public.training_sync_runs where outcome='failed' and created_at>now()-interval '24 hours' group by platform,error_code order by count(*) desc limit 12) x),'[]'::jsonb),
    'recent_private_access',coalesce((select jsonb_agg(x) from (select a.actor_id,p.handle actor_handle,a.target_user_id,a.resource,a.created_at from private.training_access_audit a join public.profiles p on p.id=a.actor_id order by a.created_at desc limit 20) x),'[]'::jsonb)
  );
end $$;

-- Automatic jobs are enqueued in small batches; pg_cron invokes the Edge worker separately.
create or replace function public.enqueue_due_training_syncs(limit_count integer default 50)
returns integer language plpgsql security definer set search_path=public,pg_catalog
as $$
declare v_count integer;
begin
  insert into public.training_sync_jobs(user_id,external_account_id,platform,kind,requested_by,priority)
  select a.user_id,a.id,a.platform,case when a.last_success_at is null then 'initial' else 'incremental' end,'automatic',0
  from public.external_accounts a where a.status in ('active','degraded') and a.next_sync_at<=now()
    and not exists(select 1 from public.training_sync_jobs j where j.external_account_id=a.id and j.status in ('queued','running'))
  order by a.next_sync_at limit least(greatest(coalesce(limit_count,50),1),200) on conflict do nothing;
  get diagnostics v_count=row_count;return v_count;
end $$;

grant execute on function public.update_training_privacy(boolean,boolean,boolean,boolean),public.enqueue_training_sync(text),public.get_my_training_dashboard(),public.get_training_profile(uuid),public.get_training_map(uuid),public.get_training_heatmap(uuid,date,date,text),public.get_training_recommendations(integer),public.skip_training_recommendation(uuid),public.get_training_sync_status(),public.get_explorer_leaderboard(integer),public.get_training_access_audit(uuid,integer),public.get_training_admin_metrics() to authenticated;
grant execute on function public.get_training_profile(uuid),public.get_training_map(uuid),public.get_training_heatmap(uuid,date,date,text),public.get_explorer_leaderboard(integer) to anon;
revoke execute on function public.update_training_privacy(boolean,boolean,boolean,boolean),public.enqueue_training_sync(text),public.get_my_training_dashboard(),public.get_training_recommendations(integer),public.skip_training_recommendation(uuid),public.get_training_sync_status(),public.get_training_access_audit(uuid,integer),public.get_training_admin_metrics() from public,anon;
revoke execute on function public.claim_training_sync_job(text),public.acquire_training_platform_lease(text),public.finish_training_sync_job(uuid,text,jsonb,integer,integer,integer,text,text,boolean),public.refresh_training_user(uuid),public.enqueue_due_training_syncs(integer) from public,anon,authenticated;
revoke execute on function private.refresh_training_aggregates(uuid),private.refresh_training_mastery(uuid),private.refresh_training_recommendations(uuid),private.build_training_map(uuid),private.build_training_accounts(uuid),private.build_public_training_accounts(uuid) from public,anon,authenticated;

-- Optional scheduler bootstrap. Configure Vault secrets named project_url and training_worker_secret,
-- then schedule the Edge worker from the Supabase Cron dashboard every five minutes.
comment on function public.enqueue_due_training_syncs(integer) is 'Called by the scheduled training worker before it claims jobs.';
