-- Let new users choose an existing organisation or create one during sign-up.
-- Existing organisation sign-ups join as warehouse staff; new organisation sign-ups become admin.

drop policy if exists "organisations_signup_select" on organisations;

create policy "organisations_signup_select"
  on organisations for select
  to anon, authenticated
  using (true);

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  desired_username text;
  requested_mode text;
  requested_org_id uuid;
  requested_org_name text;
  target_org uuid;
  created_new_org boolean := false;
begin
  desired_username := lower(regexp_replace(coalesce(new.raw_user_meta_data->>'username', ''), '[^a-zA-Z0-9_]', '', 'g'));
  requested_mode := coalesce(new.raw_user_meta_data->>'organisation_mode', 'existing');
  requested_org_name := nullif(trim(coalesce(new.raw_user_meta_data->>'organisation_name', '')), '');

  if length(desired_username) < 3 then
    desired_username := 'user_' || replace(left(new.id::text, 8), '-', '');
  end if;

  update public.organisation_members
  set user_id = new.id,
      status = 'active',
      updated_at = now()
  where user_id is null
    and status = 'pending'
    and lower(invited_email) = lower(coalesce(new.email, ''));

  select organisation_id
    into target_org
  from public.organisation_members
  where user_id = new.id
    and status = 'active'
  order by created_at
  limit 1;

  if target_org is null and requested_mode = 'existing' then
    begin
      requested_org_id := nullif(new.raw_user_meta_data->>'organisation_id', '')::uuid;
    exception when invalid_text_representation then
      requested_org_id := null;
    end;

    select id
      into target_org
    from public.organisations
    where id = requested_org_id
    limit 1;

    if target_org is not null then
      insert into public.organisation_members (organisation_id, user_id, role, status)
      values (target_org, new.id, 'warehouse_staff', 'active')
      on conflict (organisation_id, user_id) do update
        set status = 'active',
            updated_at = now();
    end if;
  end if;

  if target_org is null and requested_mode = 'new' and requested_org_name is not null then
    select id
      into target_org
    from public.organisations
    where lower(name) = lower(requested_org_name)
    order by created_at
    limit 1;

    if target_org is null then
      insert into public.organisations (name, created_by)
      values (requested_org_name, new.id)
      returning id into target_org;
      created_new_org := true;
    end if;

    insert into public.organisation_members (organisation_id, user_id, role, status)
    values (
      target_org,
      new.id,
      case when created_new_org then 'admin' else 'warehouse_staff' end,
      'active'
    )
    on conflict (organisation_id, user_id) do update
      set status = 'active',
          updated_at = now();
  end if;

  if target_org is null then
    select id
      into target_org
    from public.organisations
    where name = 'Org1'
    order by created_at
    limit 1;

    if target_org is null then
      insert into public.organisations (name, created_by)
      values ('Org1', new.id)
      returning id into target_org;
      created_new_org := true;
    end if;

    insert into public.organisation_members (organisation_id, user_id, role, status)
    values (
      target_org,
      new.id,
      case when created_new_org then 'admin' else 'warehouse_staff' end,
      'active'
    )
    on conflict (organisation_id, user_id) do update
      set status = 'active',
          updated_at = now();
  end if;

  insert into public.user_profiles (id, username, email, display_name, default_organisation_id)
  values (new.id, desired_username, coalesce(new.email, ''), desired_username, target_org)
  on conflict (id) do update
    set username = excluded.username,
        email = excluded.email,
        display_name = coalesce(public.user_profiles.display_name, excluded.display_name),
        default_organisation_id = coalesce(public.user_profiles.default_organisation_id, excluded.default_organisation_id),
        updated_at = now();

  return new;
end;
$$;
