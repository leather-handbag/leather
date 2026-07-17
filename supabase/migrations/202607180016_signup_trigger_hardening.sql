-- Keep auth signup resilient: profile creation must not be rolled back by
-- optional per-user initializers such as favorites or training defaults.

create or replace function private.create_default_favorite_folder()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  begin
    perform private.ensure_default_favorite_folder(new.id);
  exception when others then
    raise warning 'default favorite folder init failed for user %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function private.initialize_training_user()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_model integer;
begin
  begin
    insert into public.mastery_model_versions(version,name,config,active)
    values(1,'Leather Atlas v1','{"weights":{"breadth":0.45,"challenge":0.25,"coverage":0.20,"stability":0.10},"tag_threshold":0.7}'::jsonb,true)
    on conflict(version) do nothing;

    insert into public.training_maps(code,name,subtitle,icon,position,cf_min,cf_max,atcoder_min,atcoder_max,luogu_min,luogu_max,color,description)
    values('plains','启程平原','把基础练成可靠的本能','P',1,0,1099,-9999,399,0,1,'#76996f','模拟、枚举与基础思维构成第一张地图。')
    on conflict(code) do nothing;

    select version into v_model from public.mastery_model_versions where active limit 1;
    insert into public.training_privacy(user_id) values(new.id) on conflict do nothing;
    insert into public.map_unlocks(user_id,map_code,model_version,detail)
    values(new.id,'plains',coalesce(v_model,1),'{"reason":"starting_map"}'::jsonb)
    on conflict do nothing;
  exception when others then
    raise warning 'training init failed for user %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_catalog
as $$
declare
  v_base text;
  v_handle text;
  v_name text;
begin
  v_name := trim(regexp_replace(normalize(coalesce(split_part(new.email,'@',1),''),NFKC),'[[:cntrl:]]','','g'));
  v_name := left(v_name,30);
  if v_name = '' or private.profile_name_violation(v_name) is not null then
    v_name := 'user_' || substr(replace(new.id::text,'-',''),1,8);
  end if;

  v_base := lower(regexp_replace(normalize(coalesce(split_part(new.email,'@',1),''),NFKC),'[^a-zA-Z0-9_-]','','g'));
  if char_length(v_base) < 3 or v_base = 'leather-handbag' then
    v_base := 'user_' || substr(replace(new.id::text,'-',''),1,8);
  end if;
  v_handle := left(v_base,20) || '_' || substr(replace(new.id::text,'-',''),1,6);

  begin
    insert into public.profiles(id,handle,display_name,avatar_url)
    values(new.id,v_handle,v_name,null);
  exception when unique_violation then
    insert into public.profiles(id,handle,display_name,avatar_url)
    values(
      new.id,
      'user_' || substr(replace(new.id::text,'-',''),1,12),
      'user_' || substr(replace(new.id::text,'-',''),1,8),
      null
    )
    on conflict(id) do nothing;
  end;

  return new;
end $$;

comment on function public.handle_new_user() is 'Creates a safe profile during auth signup; optional after-insert initializers are hardened separately.';
