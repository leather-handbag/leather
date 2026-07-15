-- Leather social graph, post engagement, version history, unified notifications,
-- achievements and ten-draw luck ranking.

update public.profiles set blog_autosave_minutes = 30 where blog_autosave_minutes not in (0,30);
alter table public.profiles alter column blog_autosave_minutes set default 30;
alter table public.profiles drop constraint if exists profiles_blog_autosave_minutes_check;
alter table public.profiles add constraint profiles_blog_autosave_minutes_check check (blog_autosave_minutes in (0,30));

create or replace function public.get_blog_autosave_minutes()
returns integer language sql stable security definer set search_path = public, pg_catalog
as $$ select coalesce((select blog_autosave_minutes from public.profiles where id = auth.uid()),30) $$;

create or replace function public.set_blog_autosave_minutes(p_minutes integer)
returns void language plpgsql security definer set search_path = public, private, pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if private.is_banned(auth.uid()) then raise exception 'account banned'; end if;
  if p_minutes not in (0,30) then raise exception 'invalid autosave setting'; end if;
  update public.profiles set blog_autosave_minutes = p_minutes, updated_at = now() where id = auth.uid();
end $$;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='posts_id_user_unique' and conrelid='public.posts'::regclass) then
    alter table public.posts add constraint posts_id_user_unique unique(id,user_id);
  end if;
end $$;

create table if not exists public.post_snapshots (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null,
  user_id uuid not null,
  title text not null,
  summary text not null default '',
  content text not null,
  tags text[] not null default '{}',
  visibility text not null check (visibility in ('private','public')),
  created_at timestamptz not null default now(),
  constraint post_snapshots_post_owner_fk foreign key(post_id,user_id) references public.posts(id,user_id) on delete cascade
);
create index if not exists post_snapshots_post_created_idx on public.post_snapshots(post_id,created_at desc);

create or replace function private.snapshot_post_version()
returns trigger language plpgsql security definer set search_path = public, pg_catalog
as $$
declare v_row public.posts;
begin
  v_row := case when tg_op='INSERT' then new else old end;
  insert into public.post_snapshots(post_id,user_id,title,summary,content,tags,visibility,created_at)
  values(v_row.id,v_row.user_id,v_row.title,v_row.summary,v_row.content,v_row.tags,v_row.visibility,
         case when tg_op='INSERT' then v_row.created_at else now() end);
  delete from public.post_snapshots s
  where s.post_id=v_row.id and s.id not in (
    select keep.id from public.post_snapshots keep where keep.post_id=v_row.id order by keep.created_at desc limit 100
  );
  return new;
end $$;
drop trigger if exists x_snapshot_post_version on public.posts;
create trigger x_snapshot_post_version after insert or update of title,summary,content,tags,visibility on public.posts
for each row execute function private.snapshot_post_version();

insert into public.post_snapshots(post_id,user_id,title,summary,content,tags,visibility,created_at)
select p.id,p.user_id,p.title,p.summary,p.content,p.tags,p.visibility,p.created_at
from public.posts p where not exists(select 1 from public.post_snapshots s where s.post_id=p.id);

create or replace function public.restore_post_snapshot(snapshot_id uuid)
returns public.posts language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_snap public.post_snapshots; v_post public.posts;
begin
  if auth.uid() is null or private.is_banned(auth.uid()) then raise exception 'forbidden'; end if;
  select * into v_snap from public.post_snapshots where id=snapshot_id and user_id=auth.uid();
  if not found then raise exception 'snapshot not found'; end if;
  update public.posts set title=v_snap.title,summary=v_snap.summary,content=v_snap.content,tags=v_snap.tags,
    visibility=v_snap.visibility,updated_at=now()
  where id=v_snap.post_id and user_id=auth.uid() returning * into v_post;
  if not found then raise exception 'post not found'; end if;
  return v_post;
end $$;

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id)
);
create index if not exists post_likes_user_idx on public.post_likes(user_id,created_at desc);

create table if not exists public.favorite_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint favorite_folders_name_length check(char_length(name) between 1 and 30),
  constraint favorite_folders_id_user_unique unique(id,user_id)
);
create unique index if not exists favorite_folders_user_name_uidx on public.favorite_folders(user_id,lower(name));
create unique index if not exists favorite_folders_default_uidx on public.favorite_folders(user_id) where is_default;

create table if not exists public.post_favorites (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  folder_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(post_id,user_id),
  constraint post_favorites_folder_owner_fk foreign key(folder_id,user_id) references public.favorite_folders(id,user_id) on delete cascade
);
create index if not exists post_favorites_folder_idx on public.post_favorites(folder_id,created_at desc);

create or replace function private.ensure_default_favorite_folder(target_user uuid)
returns uuid language plpgsql security definer set search_path = public, pg_catalog
as $$
declare v_id uuid;
begin
  select id into v_id from public.favorite_folders where user_id=target_user and is_default limit 1;
  if v_id is null then
    insert into public.favorite_folders(user_id,name,is_default) values(target_user,'默认收藏夹',true)
    on conflict(user_id) where is_default do update set updated_at=now() returning id into v_id;
  end if;
  return v_id;
end $$;

insert into public.favorite_folders(user_id,name,is_default)
select p.id,'默认收藏夹',true from public.profiles p
where not exists(select 1 from public.favorite_folders f where f.user_id=p.id and f.is_default)
on conflict do nothing;

create or replace function private.create_default_favorite_folder()
returns trigger language plpgsql security definer set search_path = public, private, pg_catalog
as $$ begin perform private.ensure_default_favorite_folder(new.id); return new; end $$;
drop trigger if exists z_create_default_favorite_folder on public.profiles;
create trigger z_create_default_favorite_folder after insert on public.profiles
for each row execute function private.create_default_favorite_folder();

create or replace function public.favorite_post(target_post uuid, target_folder uuid default null)
returns uuid language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_folder uuid; v_user uuid:=auth.uid();
begin
  if v_user is null or private.is_banned(v_user) then raise exception 'forbidden'; end if;
  if not exists(select 1 from public.posts where id=target_post and visibility='public') then raise exception 'post not public'; end if;
  if target_folder is null then v_folder:=private.ensure_default_favorite_folder(v_user);
  else select id into v_folder from public.favorite_folders where id=target_folder and user_id=v_user; end if;
  if v_folder is null then raise exception 'folder not found'; end if;
  insert into public.post_favorites(post_id,user_id,folder_id) values(target_post,v_user,v_folder)
  on conflict(post_id,user_id) do update set folder_id=excluded.folder_id,created_at=now();
  return v_folder;
end $$;

create or replace view public.post_engagement as
select p.id as post_id, count(distinct l.user_id)::integer as like_count,
       count(distinct f.user_id)::integer as favorite_count
from public.posts p
left join public.post_likes l on l.post_id=p.id
left join public.post_favorites f on f.post_id=p.id
where p.visibility='public'
group by p.id;

create table if not exists public.user_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(follower_id,following_id),
  constraint user_follows_not_self check(follower_id<>following_id)
);
create index if not exists user_follows_following_idx on public.user_follows(following_id,created_at desc);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete cascade,
  type text not null check(type in ('mention','discussion_reply','post_comment','comment_reply','follow','system','achievement')),
  source_table text not null,
  source_id uuid not null,
  message text not null default '',
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_message_length check(char_length(message)<=300),
  unique(recipient_id,type,source_id)
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_id,created_at desc);
create index if not exists notifications_unread_idx on public.notifications(recipient_id,created_at desc) where read_at is null;

insert into public.notifications(recipient_id,actor_id,type,source_table,source_id,message,created_at,read_at)
select recipient_id,actor_id,'mention','station_comments',discussion_id,'在讨论区提及了你',created_at,read_at
from public.mention_notifications on conflict do nothing;

create or replace function private.push_notification(target_user uuid, actor uuid, notice_type text, source_name text, source uuid, notice_message text)
returns void language plpgsql security definer set search_path = public, pg_catalog
as $$
begin
  if target_user is null or source is null or target_user=actor then return; end if;
  insert into public.notifications(recipient_id,actor_id,type,source_table,source_id,message)
  values(target_user,actor,notice_type,left(source_name,60),source,left(coalesce(notice_message,''),300))
  on conflict(recipient_id,type,source_id) do update set actor_id=excluded.actor_id,message=excluded.message,created_at=now(),read_at=null;
end $$;

create or replace function private.sync_discussion_mentions()
returns trigger language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_recipient uuid; v_reply_user uuid;
begin
  delete from public.mention_notifications where discussion_id=new.id;
  delete from public.notifications where source_id=new.id and type in ('mention','discussion_reply');
  select user_id into v_reply_user from public.station_comments where id=new.reply_to;
  if v_reply_user is not null then
    perform private.push_notification(v_reply_user,new.user_id,'discussion_reply','station_comments',new.id,'回复了你的讨论');
  end if;
  for v_recipient in
    select distinct p.id from regexp_matches(lower(coalesce(new.content,'')), '(?:^|[^a-z0-9_-])@([a-z0-9][a-z0-9_-]{2,29})','g') hit
    join public.profiles p on lower(p.handle)=hit[1]
    where p.id<>new.user_id and p.id is distinct from v_reply_user
  loop
    insert into public.mention_notifications(recipient_id,actor_id,discussion_id) values(v_recipient,new.user_id,new.id)
    on conflict(recipient_id,discussion_id) do nothing;
    perform private.push_notification(v_recipient,new.user_id,'mention','station_comments',new.id,'在讨论区提及了你');
  end loop;
  return new;
end $$;

alter table public.post_comments add column if not exists reply_to uuid references public.post_comments(id) on delete set null;
create index if not exists post_comments_reply_idx on public.post_comments(reply_to) where reply_to is not null;

create or replace function private.sync_post_comment_notifications()
returns trigger language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_post_author uuid; v_reply_user uuid; v_recipient uuid;
begin
  delete from public.notifications where source_id=new.id and type in ('mention','post_comment','comment_reply');
  select user_id into v_post_author from public.posts where id=new.post_id;
  select user_id into v_reply_user from public.post_comments where id=new.reply_to;
  if v_reply_user is not null then perform private.push_notification(v_reply_user,new.user_id,'comment_reply','post_comments',new.id,'回复了你的文章评论'); end if;
  if v_post_author is distinct from v_reply_user then perform private.push_notification(v_post_author,new.user_id,'post_comment','post_comments',new.id,'评论了你的文章'); end if;
  for v_recipient in
    select distinct p.id from regexp_matches(lower(coalesce(new.content,'')), '(?:^|[^a-z0-9_-])@([a-z0-9][a-z0-9_-]{2,29})','g') hit
    join public.profiles p on lower(p.handle)=hit[1]
    where p.id<>new.user_id and p.id is distinct from v_reply_user and p.id is distinct from v_post_author
  loop perform private.push_notification(v_recipient,new.user_id,'mention','post_comments',new.id,'在文章评论中提及了你'); end loop;
  return new;
end $$;
drop trigger if exists a_sync_post_comment_notifications on public.post_comments;
create trigger a_sync_post_comment_notifications after insert or update of content,reply_to on public.post_comments
for each row execute function private.sync_post_comment_notifications();

create or replace function private.notify_follow()
returns trigger language plpgsql security definer set search_path = public, private, pg_catalog
as $$ begin perform private.push_notification(new.following_id,new.follower_id,'follow','user_follows',new.follower_id,'关注了你'); return new; end $$;
drop trigger if exists a_notify_follow on public.user_follows;
create trigger a_notify_follow after insert on public.user_follows for each row execute function private.notify_follow();

create table if not exists public.achievement_definitions (
  code text primary key,
  name text not null,
  description text not null,
  icon text not null,
  sort_order integer not null default 0
);
insert into public.achievement_definitions(code,name,description,icon,sort_order) values
('streak_3','初露锋芒','连续签到 3 天','✦',10),('streak_7','持之以恒','连续签到 7 天','◆',20),('streak_30','月度坚持','连续签到 30 天','⬢',30),
('posts_1','首篇文章','发表 1 篇公开博客','✎',40),('posts_5','知识分享者','发表 5 篇公开博客','▤',50),('posts_20','专栏作者','发表 20 篇公开博客','▥',60),
('discussions_1','第一次发言','发表 1 条讨论','☵',70),('discussions_10','活跃讨论者','发表 10 条讨论','☷',80),('discussions_50','社区之声','发表 50 条讨论','◉',90),
('followers_10','受到关注','获得 10 位粉丝','♙',100),('followers_50','社区影响力','获得 50 位粉丝','♛',110)
on conflict(code) do update set name=excluded.name,description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order;

create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  code text not null references public.achievement_definitions(code) on delete restrict,
  detail text not null default '',
  achieved_at timestamptz not null default now(),
  unique(user_id,code)
);
create index if not exists user_achievements_user_idx on public.user_achievements(user_id,achieved_at);

create or replace function private.award_achievement(target_user uuid, target_code text, target_detail text default '')
returns void language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_id uuid; v_name text;
begin
  insert into public.user_achievements(user_id,code,detail) values(target_user,target_code,left(coalesce(target_detail,''),200))
  on conflict(user_id,code) do nothing returning id into v_id;
  if v_id is not null then
    select name into v_name from public.achievement_definitions where code=target_code;
    perform private.push_notification(target_user,null,'achievement','user_achievements',v_id,'解锁成就：'||coalesce(v_name,target_code));
  end if;
end $$;

create or replace function private.refresh_achievements(target_user uuid)
returns void language plpgsql security definer set search_path = public, private, pg_catalog
as $$
declare v_posts integer; v_discussions integer; v_followers integer; v_streak integer;
begin
  if target_user is null then return; end if;
  select count(*) into v_posts from public.posts where user_id=target_user and visibility='public';
  select count(*) into v_discussions from public.station_comments where user_id=target_user;
  select count(*) into v_followers from public.user_follows where following_id=target_user;
  select count(*) into v_streak from (
    select d.checkin_date,row_number() over(order by d.checkin_date desc) rn
    from public.daily_checkins d where d.user_id=target_user and d.checkin_date<=private.china_today()
  ) x where x.checkin_date=private.china_today()-(x.rn::integer-1);
  if v_streak>=3 then perform private.award_achievement(target_user,'streak_3',v_streak||' 天'); end if;
  if v_streak>=7 then perform private.award_achievement(target_user,'streak_7',v_streak||' 天'); end if;
  if v_streak>=30 then perform private.award_achievement(target_user,'streak_30',v_streak||' 天'); end if;
  if v_posts>=1 then perform private.award_achievement(target_user,'posts_1',v_posts||' 篇'); end if;
  if v_posts>=5 then perform private.award_achievement(target_user,'posts_5',v_posts||' 篇'); end if;
  if v_posts>=20 then perform private.award_achievement(target_user,'posts_20',v_posts||' 篇'); end if;
  if v_discussions>=1 then perform private.award_achievement(target_user,'discussions_1',v_discussions||' 条'); end if;
  if v_discussions>=10 then perform private.award_achievement(target_user,'discussions_10',v_discussions||' 条'); end if;
  if v_discussions>=50 then perform private.award_achievement(target_user,'discussions_50',v_discussions||' 条'); end if;
  if v_followers>=10 then perform private.award_achievement(target_user,'followers_10',v_followers||' 人'); end if;
  if v_followers>=50 then perform private.award_achievement(target_user,'followers_50',v_followers||' 人'); end if;
end $$;

create or replace function private.refresh_achievements_trigger()
returns trigger language plpgsql security definer set search_path = public, private, pg_catalog
as $$
begin
  if tg_table_name='user_follows' then perform private.refresh_achievements(new.following_id);
  else perform private.refresh_achievements(new.user_id); end if;
  return new;
end $$;
drop trigger if exists zz_refresh_post_achievements on public.posts;
create trigger zz_refresh_post_achievements after insert or update of visibility on public.posts for each row execute function private.refresh_achievements_trigger();
drop trigger if exists zz_refresh_discussion_achievements on public.station_comments;
create trigger zz_refresh_discussion_achievements after insert on public.station_comments for each row execute function private.refresh_achievements_trigger();
drop trigger if exists zz_refresh_checkin_achievements on public.daily_checkins;
create trigger zz_refresh_checkin_achievements after insert on public.daily_checkins for each row execute function private.refresh_achievements_trigger();
drop trigger if exists zz_refresh_follow_achievements on public.user_follows;
create trigger zz_refresh_follow_achievements after insert on public.user_follows for each row execute function private.refresh_achievements_trigger();

select private.refresh_achievements(id) from public.profiles;

create or replace function public.get_notifications(limit_count integer default 50)
returns table(id uuid,type text,source_table text,source_id uuid,message text,actor_id uuid,actor_handle text,actor_name text,actor_avatar text,created_at timestamptz,is_read boolean)
language plpgsql stable security definer set search_path = public, pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return query select n.id,n.type,n.source_table,n.source_id,n.message,n.actor_id,p.handle,p.display_name,p.avatar_url,n.created_at,n.read_at is not null
  from public.notifications n left join public.profiles p on p.id=n.actor_id
  where n.recipient_id=auth.uid() order by n.created_at desc limit least(greatest(coalesce(limit_count,50),1),100);
end $$;

create or replace function public.mark_notifications_read()
returns integer language plpgsql security definer set search_path = public, pg_catalog
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  update public.notifications set read_at=coalesce(read_at,now()) where recipient_id=auth.uid() and read_at is null;
  get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.get_user_achievements(target_user uuid)
returns table(code text,name text,description text,icon text,detail text,achieved_at timestamptz)
language sql stable security definer set search_path = public, pg_catalog
as $$
  select d.code,d.name,d.description,d.icon,a.detail,a.achieved_at
  from public.user_achievements a join public.achievement_definitions d on d.code=a.code
  where a.user_id=target_user order by d.sort_order,a.achieved_at
$$;

alter table public.daily_checkins drop constraint if exists daily_checkins_rarity_check;
alter table public.daily_checkins add constraint daily_checkins_rarity_check check(rarity in ('common','uncommon','rare','epic','legendary','chromatic'));
alter table public.daily_checkins drop constraint if exists daily_checkins_draw_count_check;
alter table public.daily_checkins add constraint daily_checkins_draw_count_check check(draw_count between 1 and 10);

create or replace function private.rate_checkin(number_value integer)
returns table(rarity text,label text) language plpgsql immutable set search_path = pg_catalog
as $$
declare s text:=lpad(number_value::text,6,'0');
begin
  if number_value=111101 then return query select 'chromatic','炫彩';
  elsif s ~ '^([0-9])\1{5}$' or s in ('012345','123456','234567','345678','456789','987654','876543','765432','654321','543210') then return query select 'legendary','传说';
  elsif s=reverse(s) or substring(s,1,3)=substring(s,4,3) or s ~ '^([0-9])\1{3,}' then return query select 'epic','史诗';
  elsif s ~ '([0-9])\1{2}' or s ~ '^([0-9])\1([0-9])\2([0-9])\3$' then return query select 'rare','稀有';
  elsif s ~ '([0-9])\1' or s ~ '(012|123|234|345|456|567|678|789|987|876|765|654|543|432|321|210)' then return query select 'uncommon','少见';
  else return query select 'common','普通'; end if;
end $$;

create or replace function public.daily_checkin()
returns public.daily_checkins language plpgsql security definer set search_path = public,private,pg_catalog
as $$
declare v_user uuid:=auth.uid();v_day date:=private.china_today();v_candidate integer;v_candidate_rarity text;v_candidate_label text;v_candidate_rank integer;
v_best_number integer:=0;v_best_rarity text:='common';v_best_label text:='普通';v_best_rank integer:=-1;v_row public.daily_checkins;i integer;
begin
  if v_user is null then raise exception 'authentication required'; end if;if private.is_banned(v_user) then raise exception 'account banned';end if;
  perform pg_advisory_xact_lock(hashtext(v_user::text||':'||v_day::text));select * into v_row from public.daily_checkins where user_id=v_user and checkin_date=v_day;if found then return v_row;end if;
  for i in 1..10 loop
    v_candidate:=private.random_six_digit();select rarity,label into v_candidate_rarity,v_candidate_label from private.rate_checkin(v_candidate);
    v_candidate_rank:=case v_candidate_rarity when 'chromatic' then 6 when 'legendary' then 5 when 'epic' then 4 when 'rare' then 3 when 'uncommon' then 2 else 1 end;
    if v_candidate_rank>v_best_rank then v_best_number:=v_candidate;v_best_rarity:=v_candidate_rarity;v_best_label:=v_candidate_label;v_best_rank:=v_candidate_rank;end if;
  end loop;
  insert into public.daily_checkins(user_id,checkin_date,number,rarity,rarity_label,draw_count) values(v_user,v_day,v_best_number,v_best_rarity,v_best_label,10) returning * into v_row;return v_row;
end $$;

create or replace function public.get_luck_leaderboard(period_name text default 'week')
returns table(user_id uuid,handle text,display_name text,avatar_url text,role text,name_color text,number integer,rarity text,rarity_label text,achieved_at timestamptz,rarity_rank integer)
language plpgsql stable security definer set search_path = public,private,pg_catalog
as $$
begin
  return query
  with ranked as (
    select d.*,case d.rarity when 'chromatic' then 6 when 'legendary' then 5 when 'epic' then 4 when 'rare' then 3 when 'uncommon' then 2 else 1 end rr,
      row_number() over(partition by d.user_id order by case d.rarity when 'chromatic' then 6 when 'legendary' then 5 when 'epic' then 4 when 'rare' then 3 when 'uncommon' then 2 else 1 end desc,d.created_at asc) own_rank
    from public.daily_checkins d
    where period_name='history' or d.checkin_date>=private.china_today()-(extract(isodow from private.china_today())::integer-1)
  )
  select s.id,s.handle,s.display_name,s.avatar_url,s.role,s.name_color,r.number,r.rarity,r.rarity_label,r.created_at,r.rr
  from ranked r join public.public_profile_stats s on s.id=r.user_id where r.own_rank=1
  order by r.rr desc,r.created_at asc limit 100;
end $$;

create or replace view public.public_profile_stats as
select p.id,p.handle,p.display_name,p.avatar_url,p.bio,p.role,p.joined_on,
       coalesce(c.total,0)::integer as checkin_count,
       (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))::integer as score,
       c.last_checkin_date,
       case when p.role in ('admin','owner') then 'purple'
            when (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))<0 then 'gray'
            when (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))<5 then 'blue'
            when (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))<10 then 'green'
            when (5*coalesce(c.total,0)-greatest(0,(private.china_today()-p.joined_on)-coalesce(c.past,0)))<30 then 'orange' else 'red' end as name_color,
       coalesce(f.followers,0)::integer as follower_count,coalesce(g.following,0)::integer as following_count
from public.profiles p
left join lateral(select count(*) total,count(*) filter(where d.checkin_date<private.china_today()) past,max(d.checkin_date) last_checkin_date from public.daily_checkins d where d.user_id=p.id)c on true
left join lateral(select count(*) followers from public.user_follows u where u.following_id=p.id)f on true
left join lateral(select count(*) following from public.user_follows u where u.follower_id=p.id)g on true
where p.banned_at is null;

create or replace function public.review_avatar_request(request_id uuid,is_approved boolean,note text default '')
returns text language plpgsql security definer set search_path = public,private,pg_catalog
as $$
declare v_req public.avatar_requests;v_target_role text;v_note text:=left(trim(coalesce(note,'')),300);
begin
  select * into v_req from public.avatar_requests where id=request_id and status='pending' for update;if not found then raise exception 'avatar request not found';end if;
  select p.role into v_target_role from public.profiles p where p.id=v_req.user_id;
  if not private.is_owner(auth.uid()) and not(private.is_staff(auth.uid()) and v_target_role='user' and v_req.user_id<>auth.uid()) then raise exception 'forbidden';end if;
  if coalesce(is_approved,false) then perform set_config('app.privileged_profile_write','true',true);update public.profiles set avatar_url=v_req.avatar_url,updated_at=now() where id=v_req.user_id;end if;
  update public.avatar_requests set status=case when coalesce(is_approved,false) then 'approved' else 'rejected' end,reviewer_id=auth.uid(),review_note=v_note,reviewed_at=now() where id=v_req.id;
  insert into private.moderation_events(user_id,source_table,content_id,reason,actor_id) values(v_req.user_id,'avatar_requests',v_req.id,case when coalesce(is_approved,false) then '头像审核通过' else '头像审核拒绝：'||coalesce(nullif(v_note,''),'未填写原因') end,auth.uid());
  perform private.push_notification(v_req.user_id,auth.uid(),'system','avatar_requests',v_req.id,case when coalesce(is_approved,false) then '你的头像已通过审核' else '你的头像未通过审核'||case when v_note<>'' then '：'||v_note else '' end end);
  return v_req.object_path;
end $$;

alter table public.post_snapshots enable row level security;
alter table public.post_likes enable row level security;
alter table public.favorite_folders enable row level security;
alter table public.post_favorites enable row level security;
alter table public.user_follows enable row level security;
alter table public.notifications enable row level security;
alter table public.achievement_definitions enable row level security;
alter table public.user_achievements enable row level security;

create policy post_snapshots_read on public.post_snapshots for select to authenticated using(user_id=auth.uid() or private.is_staff(auth.uid()));
create policy post_likes_read on public.post_likes for select to anon,authenticated using(exists(select 1 from public.posts p where p.id=post_id and p.visibility='public'));
create policy post_likes_insert on public.post_likes for insert to authenticated with check(user_id=auth.uid() and not private.is_banned(auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and p.visibility='public'));
create policy post_likes_delete on public.post_likes for delete to authenticated using(user_id=auth.uid());
create policy favorite_folders_all on public.favorite_folders for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and not private.is_banned(auth.uid()));
create policy post_favorites_read on public.post_favorites for select to authenticated using(user_id=auth.uid());
create policy post_favorites_delete on public.post_favorites for delete to authenticated using(user_id=auth.uid());
create policy user_follows_read on public.user_follows for select to anon,authenticated using(true);
create policy user_follows_insert on public.user_follows for insert to authenticated with check(follower_id=auth.uid() and not private.is_banned(auth.uid()));
create policy user_follows_delete on public.user_follows for delete to authenticated using(follower_id=auth.uid());
create policy notifications_read on public.notifications for select to authenticated using(recipient_id=auth.uid());
create policy achievement_definitions_read on public.achievement_definitions for select to anon,authenticated using(true);
create policy user_achievements_read on public.user_achievements for select to anon,authenticated using(true);

revoke all on public.post_snapshots,public.favorite_folders,public.post_favorites,public.notifications from public,anon,authenticated;
grant select on public.post_snapshots,public.favorite_folders,public.post_favorites to authenticated;
grant insert,update,delete on public.favorite_folders to authenticated;
grant select,insert,delete on public.post_likes,public.user_follows to authenticated;
grant select on public.post_likes,public.user_follows,public.achievement_definitions,public.user_achievements,public.post_engagement to anon,authenticated;

grant execute on function public.restore_post_snapshot(uuid),public.favorite_post(uuid,uuid),public.get_notifications(integer),public.mark_notifications_read() to authenticated;
grant execute on function public.get_user_achievements(uuid),public.get_luck_leaderboard(text) to anon,authenticated;
revoke execute on function public.restore_post_snapshot(uuid),public.favorite_post(uuid,uuid),public.get_notifications(integer),public.mark_notifications_read() from public,anon;
revoke execute on function private.ensure_default_favorite_folder(uuid),private.create_default_favorite_folder(),private.snapshot_post_version(),private.push_notification(uuid,uuid,text,text,uuid,text),private.sync_post_comment_notifications(),private.notify_follow(),private.award_achievement(uuid,text,text),private.refresh_achievements(uuid),private.refresh_achievements_trigger() from public,anon,authenticated;

