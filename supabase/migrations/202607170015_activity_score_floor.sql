-- Keep long absences visible without allowing activity scores to decrease forever.

create or replace view public.public_profile_stats as
select q.id,q.handle,q.display_name,q.avatar_url,q.bio,q.role,q.joined_on,
       q.checkin_count,greatest(-30,q.raw_score)::integer as score,q.last_checkin_date,
       case when q.role in ('admin','owner') then 'purple'
            when greatest(-30,q.raw_score)<0 then 'gray'
            when greatest(-30,q.raw_score)<5 then 'blue'
            when greatest(-30,q.raw_score)<10 then 'green'
            when greatest(-30,q.raw_score)<30 then 'orange' else 'red' end as name_color,
       q.follower_count,q.following_count,q.avatar_frame
from (
  select p.id,p.handle,p.display_name,p.avatar_url,p.bio,p.role,p.joined_on,
         coalesce(c.total,0)::integer as checkin_count,
         (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))::integer as raw_score,
         c.last_checkin_date,
         coalesce(f.followers,0)::integer as follower_count,coalesce(g.following,0)::integer as following_count,
         case when fd.code is null then null else jsonb_build_object('code',fd.code,'name',fd.name,'rarity',fd.rarity,'style_class',fd.style_class) end as avatar_frame
  from public.profiles p
  left join lateral(select count(*) total,count(*) filter(where d.checkin_date<private.china_today()) past,max(d.checkin_date) last_checkin_date from public.daily_checkins d where d.user_id=p.id)c on true
  left join lateral(select count(*) followers from public.user_follows u where u.following_id=p.id)f on true
  left join lateral(select count(*) following from public.user_follows u where u.follower_id=p.id)g on true
  left join public.avatar_frame_definitions fd on fd.code=p.equipped_avatar_frame
  where p.banned_at is null
) q;

comment on view public.public_profile_stats is 'Public profile DTO. Activity score is bounded below at -30.';
