-- Backfill profiles for existing auth users so organisation admins can see
-- member username/email instead of raw user ids.

insert into public.user_profiles (id, username, email, display_name, default_organisation_id)
select
  users.id,
  lower(
    regexp_replace(
      coalesce(
        nullif(users.raw_user_meta_data->>'username', ''),
        split_part(coalesce(users.email, ''), '@', 1),
        'user_' || replace(left(users.id::text, 8), '-', '')
      ),
      '[^a-zA-Z0-9_]',
      '',
      'g'
    )
  ) as username,
  coalesce(users.email, '') as email,
  coalesce(
    nullif(users.raw_user_meta_data->>'username', ''),
    split_part(coalesce(users.email, ''), '@', 1),
    'Member'
  ) as display_name,
  memberships.organisation_id
from auth.users users
left join lateral (
  select organisation_id
  from public.organisation_members
  where user_id = users.id
    and status = 'active'
  order by created_at
  limit 1
) memberships on true
where not exists (
  select 1
  from public.user_profiles profiles
  where profiles.id = users.id
)
on conflict (id) do nothing;

update public.user_profiles profiles
set email = coalesce(nullif(profiles.email, ''), users.email, ''),
    display_name = coalesce(nullif(profiles.display_name, ''), profiles.username),
    default_organisation_id = coalesce(profiles.default_organisation_id, memberships.organisation_id),
    updated_at = now()
from auth.users users
left join lateral (
  select organisation_id
  from public.organisation_members
  where user_id = users.id
    and status = 'active'
  order by created_at
  limit 1
) memberships on true
where profiles.id = users.id;
