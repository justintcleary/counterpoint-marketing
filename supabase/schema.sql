-- =====================================================================
-- counterpoint.marketing portal
-- Run this in Supabase: Dashboard > SQL Editor > New query > Run.
-- Safe to re-run: every statement is idempotent.
--
-- Three kinds of account, all in public.profiles.role:
--   creator  applies to campaigns and delivers content
--   client   a brand or organization, briefs campaigns and reviews work
--   admin    counterpoint staff, sees and controls everything
-- =====================================================================

-- ---------- Tables ----------------------------------------------------

create table if not exists public.clients (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.profiles (
  id                uuid primary key references auth.users on delete cascade,
  email             text not null,
  full_name         text,
  handles           text,          -- other platforms, free text
  tiktok_handle     text,
  instagram_handle  text,
  youtube_handle    text,
  x_handle          text,
  audience_size     text,
  niche             text,          -- legacy free text, superseded by interests
  interests         text[] not null default '{}',
  location          text,
  age               int,
  gender            text,
  political_leaning text,
  notes             text,
  status            text not null default 'pending'
                    check (status in ('pending','approved','rejected')),
  role              text not null default 'creator',
  client_id         uuid references public.clients on delete set null,
  created_at        timestamptz not null default now()
);

create table if not exists public.campaigns (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  client_name     text,
  client_id       uuid references public.clients on delete set null,
  summary         text,
  brief           text,
  platforms       text,
  deliverables    text,
  rate            text,
  deadline        date,
  target_gender   text default 'any',
  target_age_min  int,
  target_age_max  int,
  target_leaning  text default 'any',
  target_location text,
  target_niche    text,
  status          text not null default 'draft',
  created_at      timestamptz not null default now()
);

create table if not exists public.applications (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns on delete cascade,
  creator_id   uuid not null references public.profiles on delete cascade,
  pitch        text,
  status       text not null default 'submitted'
               check (status in ('submitted','accepted','declined')),
  created_at   timestamptz not null default now(),
  unique (campaign_id, creator_id)
);

-- One row per piece of content somebody owes on a campaign.
create table if not exists public.content_items (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns on delete cascade,
  creator_id   uuid not null references public.profiles on delete cascade,
  title        text,
  platform     text,
  stage        text not null default 'not started',
  due_date     date,
  post_url     text,
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists applications_campaign_idx  on public.applications(campaign_id);
create index if not exists applications_creator_idx   on public.applications(creator_id);
create index if not exists content_campaign_idx       on public.content_items(campaign_id);
create index if not exists content_creator_idx        on public.content_items(creator_id);

-- ---------- Migrations for projects created before these columns ------

alter table public.profiles   add column if not exists age               int;
alter table public.profiles   add column if not exists gender            text;
alter table public.profiles   add column if not exists political_leaning text;
alter table public.profiles   add column if not exists client_id         uuid references public.clients on delete set null;
alter table public.profiles   add column if not exists tiktok_handle     text;
alter table public.profiles   add column if not exists instagram_handle  text;
alter table public.profiles   add column if not exists youtube_handle    text;
alter table public.profiles   add column if not exists x_handle          text;
alter table public.profiles   add column if not exists interests         text[] not null default '{}';

-- Up to five interest tags per creator.
alter table public.profiles drop constraint if exists profiles_interests_check;
alter table public.profiles add  constraint profiles_interests_check
  check (cardinality(interests) <= 5);
create index if not exists profiles_interests_idx on public.profiles using gin(interests);

-- One-time carry-over: split the old free-text niche into tags for anyone
-- who has not picked interests yet. Creators can tidy them under My profile.
update public.profiles
set interests = coalesce((
  select array_agg(t) from (
    select lower(trim(x)) as t
    from unnest(string_to_array(niche, ',')) as x
    where trim(x) <> '' limit 5) s), '{}')
where cardinality(interests) = 0 and coalesce(niche, '') <> '';

alter table public.campaigns  add column if not exists target_gender   text default 'any';
alter table public.campaigns  add column if not exists target_age_min  int;
alter table public.campaigns  add column if not exists target_age_max  int;
alter table public.campaigns  add column if not exists target_leaning  text default 'any';
alter table public.campaigns  add column if not exists target_location text;
alter table public.campaigns  add column if not exists target_niche    text;
alter table public.campaigns  add column if not exists client_id       uuid references public.clients on delete set null;

create index if not exists campaigns_client_idx       on public.campaigns(client_id);
create index if not exists profiles_client_idx        on public.profiles(client_id);

-- ---------- Controlled vocabularies -----------------------------------
-- Creators may always decline to answer, so demographic columns stay
-- nullable and carry an explicit "prefer not to say" value.

alter table public.profiles drop constraint if exists profiles_gender_check;
alter table public.profiles add  constraint profiles_gender_check
  check (gender is null or gender in
    ('woman','man','non-binary','other','prefer not to say'));

alter table public.profiles drop constraint if exists profiles_leaning_check;
alter table public.profiles add  constraint profiles_leaning_check
  check (political_leaning is null or political_leaning in
    ('left','lean left','moderate','lean right','right','non-political','prefer not to say'));

alter table public.profiles drop constraint if exists profiles_age_check;
alter table public.profiles add  constraint profiles_age_check
  check (age is null or (age >= 16 and age <= 100));

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add  constraint profiles_role_check
  check (role in ('creator','client','admin'));

alter table public.campaigns drop constraint if exists campaigns_target_gender_check;
alter table public.campaigns add  constraint campaigns_target_gender_check
  check (target_gender is null or target_gender in
    ('any','woman','man','non-binary'));

alter table public.campaigns drop constraint if exists campaigns_target_leaning_check;
alter table public.campaigns add  constraint campaigns_target_leaning_check
  check (target_leaning is null or target_leaning in
    ('any','left','lean left','moderate','lean right','right','non-political'));

-- draft: nobody but the owner sees it. review: submitted to counterpoint.
-- open: visible to approved creators. closed: finished or withdrawn.
alter table public.campaigns drop constraint if exists campaigns_status_check;
alter table public.campaigns add  constraint campaigns_status_check
  check (status in ('draft','review','open','closed'));

alter table public.content_items drop constraint if exists content_items_stage_check;
alter table public.content_items add  constraint content_items_stage_check
  check (stage in ('not started','drafting','submitted for review',
                   'changes requested','approved','scheduled','posted'));

create index if not exists profiles_age_idx     on public.profiles(age);
create index if not exists profiles_gender_idx  on public.profiles(gender);
create index if not exists profiles_leaning_idx on public.profiles(political_leaning);

-- ---------- Helper functions (security definer avoids RLS recursion) ---

create or replace function public.is_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_approved()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and status = 'approved' and role = 'creator');
$$;

create or replace function public.is_client()
returns boolean language sql security definer stable
set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'client' and status = 'approved');
$$;

-- The organization the caller belongs to, or null if they are not a client.
create or replace function public.my_client_id()
returns uuid language sql security definer stable
set search_path = public as $$
  select client_id from public.profiles
  where id = auth.uid() and role = 'client' and status = 'approved';
$$;

-- ---------- Auto-create a profile when someone signs up ---------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
declare
  want_client boolean := coalesce(new.raw_user_meta_data->>'account_type','creator') = 'client';
  company     text    := nullif(trim(new.raw_user_meta_data->>'company'),'');
  org_id      uuid;
begin
  -- A client signup carries a company name. Reuse the organization if we
  -- already know it so two people from the same brand land in one account.
  if want_client and company is not null then
    select id into org_id from public.clients
      where lower(name) = lower(company) limit 1;
    if org_id is null then
      insert into public.clients (name) values (company) returning id into org_id;
    end if;
  end if;

  insert into public.profiles (
    id, email, full_name, handles,
    tiktok_handle, instagram_handle, youtube_handle, x_handle,
    audience_size, niche, interests, location,
    age, gender, political_leaning, notes, role, client_id)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'handles',
    nullif(new.raw_user_meta_data->>'tiktok_handle',''),
    nullif(new.raw_user_meta_data->>'instagram_handle',''),
    nullif(new.raw_user_meta_data->>'youtube_handle',''),
    nullif(new.raw_user_meta_data->>'x_handle',''),
    new.raw_user_meta_data->>'audience_size',
    new.raw_user_meta_data->>'niche',
    coalesce((select array_agg(lower(trim(x)))
              from jsonb_array_elements_text(
                case when jsonb_typeof(new.raw_user_meta_data->'interests') = 'array'
                     then new.raw_user_meta_data->'interests' else '[]'::jsonb end) as x
              where trim(x) <> ''), '{}'),
    new.raw_user_meta_data->>'location',
    nullif(new.raw_user_meta_data->>'age','')::int,
    nullif(new.raw_user_meta_data->>'gender',''),
    nullif(new.raw_user_meta_data->>'political_leaning',''),
    new.raw_user_meta_data->>'notes',
    case when want_client then 'client' else 'creator' end,
    org_id
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Accepting a creator opens their content tracker -----------

create or replace function public.handle_application_accepted()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted'
     and not exists (select 1 from public.content_items
                     where campaign_id = new.campaign_id
                       and creator_id  = new.creator_id) then
    insert into public.content_items (campaign_id, creator_id, title, platform, due_date)
    select new.campaign_id, new.creator_id,
           coalesce(nullif(c.deliverables,''), 'Deliverable'),
           c.platforms, c.deadline
    from public.campaigns c where c.id = new.campaign_id;
  end if;
  return new;
end; $$;

drop trigger if exists on_application_accepted on public.applications;
create trigger on_application_accepted
  after update on public.applications
  for each row execute function public.handle_application_accepted();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists content_items_touch on public.content_items;
create trigger content_items_touch
  before update on public.content_items
  for each row execute function public.touch_updated_at();

-- ---------- Row level security ----------------------------------------

alter table public.clients       enable row level security;
alter table public.profiles      enable row level security;
alter table public.campaigns     enable row level security;
alter table public.applications  enable row level security;
alter table public.content_items enable row level security;

-- clients: you can read your own organization; admins do anything
drop policy if exists clients_select_own on public.clients;
drop policy if exists clients_admin_all  on public.clients;

create policy clients_select_own on public.clients
  for select using (id = public.my_client_id());

create policy clients_admin_all on public.clients
  for all using (public.is_admin()) with check (public.is_admin());

-- profiles: you can read and edit your own row; admins can do anything.
-- Clients never read this table directly, they go through creator_directory.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists profiles_admin_all  on public.profiles;

create policy profiles_select_own on public.profiles
  for select using (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid()
    and status    = (select status    from public.profiles where id = auth.uid())
    and role      = (select role      from public.profiles where id = auth.uid())
    and client_id is not distinct from (select client_id from public.profiles where id = auth.uid()));

create policy profiles_admin_all on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- campaigns: approved creators see open ones. Clients see and manage their
-- own, but cannot publish: only counterpoint moves a campaign to open.
drop policy if exists campaigns_select_open   on public.campaigns;
drop policy if exists campaigns_client_select on public.campaigns;
drop policy if exists campaigns_client_insert on public.campaigns;
drop policy if exists campaigns_client_update on public.campaigns;
drop policy if exists campaigns_admin_all     on public.campaigns;

create policy campaigns_select_open on public.campaigns
  for select using (status = 'open' and public.is_approved());

create policy campaigns_client_select on public.campaigns
  for select using (client_id is not null and client_id = public.my_client_id());

create policy campaigns_client_insert on public.campaigns
  for insert with check (
    client_id = public.my_client_id() and status in ('draft','review'));

create policy campaigns_client_update on public.campaigns
  for update using (client_id is not null and client_id = public.my_client_id())
  with check (client_id = public.my_client_id() and status in ('draft','review','closed'));

create policy campaigns_admin_all on public.campaigns
  for all using (public.is_admin()) with check (public.is_admin());

-- applications: creators manage their own, clients read the ones on their
-- campaigns, admins do anything. Clients cannot write here: who gets on a
-- campaign is counterpoint's call.
drop policy if exists applications_select_own    on public.applications;
drop policy if exists applications_insert_own    on public.applications;
drop policy if exists applications_client_select on public.applications;
drop policy if exists applications_admin_all     on public.applications;

create policy applications_select_own on public.applications
  for select using (creator_id = auth.uid());

create policy applications_insert_own on public.applications
  for insert with check (
    creator_id = auth.uid()
    and public.is_approved()
    and exists (select 1 from public.campaigns c where c.id = campaign_id and c.status = 'open')
  );

create policy applications_client_select on public.applications
  for select using (exists (
    select 1 from public.campaigns c
    where c.id = campaign_id and c.client_id = public.my_client_id()));

create policy applications_admin_all on public.applications
  for all using (public.is_admin()) with check (public.is_admin());

-- content items: the creator who owes the work and the client who is paying
-- for it both see and update it. Admins do anything.
drop policy if exists content_creator_select on public.content_items;
drop policy if exists content_creator_update on public.content_items;
drop policy if exists content_client_select  on public.content_items;
drop policy if exists content_client_update  on public.content_items;
drop policy if exists content_admin_all      on public.content_items;

create policy content_creator_select on public.content_items
  for select using (creator_id = auth.uid());

create policy content_creator_update on public.content_items
  for update using (creator_id = auth.uid())
  with check (creator_id = auth.uid());

create policy content_client_select on public.content_items
  for select using (exists (
    select 1 from public.campaigns c
    where c.id = campaign_id and c.client_id = public.my_client_id()));

create policy content_client_update on public.content_items
  for update using (exists (
    select 1 from public.campaigns c
    where c.id = campaign_id and c.client_id = public.my_client_id()))
  with check (exists (
    select 1 from public.campaigns c
    where c.id = campaign_id and c.client_id = public.my_client_id()));

create policy content_admin_all on public.content_items
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------- Views ------------------------------------------------------
-- The directory views run as the view owner on purpose, so they can read
-- profiles without granting clients access to the table itself. That is
-- what keeps creator email addresses out of client hands: the roster is
-- counterpoint's asset, and a client only gets contact details for someone
-- already accepted onto one of their campaigns.

drop view if exists public.application_details;
create view public.application_details
with (security_invoker = true) as
  select a.id, a.status, a.pitch, a.created_at,
         c.id as campaign_id, c.title as campaign_title, c.client_name,
         p.id as creator_id, p.full_name, p.email, p.handles,
         p.tiktok_handle, p.instagram_handle, p.youtube_handle, p.x_handle,
         p.audience_size, p.niche, p.interests, p.location, p.age, p.gender, p.political_leaning
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  join public.profiles  p on p.id = a.creator_id;

drop view if exists public.creator_directory;
create view public.creator_directory
with (security_invoker = false) as
  select p.id, p.full_name, p.audience_size, p.niche, p.interests, p.location,
         p.age, p.gender, p.political_leaning, p.created_at
  from public.profiles p
  where p.status = 'approved'
    and p.role = 'creator'
    and (public.is_client() or public.is_admin());

drop view if exists public.client_application_details;
create view public.client_application_details
with (security_invoker = false) as
  select a.id, a.status, a.pitch, a.created_at,
         c.id as campaign_id, c.title as campaign_title,
         p.id as creator_id, p.full_name, p.audience_size, p.niche, p.interests,
         p.location, p.age, p.gender, p.political_leaning,
         case when a.status = 'accepted' then p.handles          else null end as handles,
         case when a.status = 'accepted' then p.tiktok_handle    else null end as tiktok_handle,
         case when a.status = 'accepted' then p.instagram_handle else null end as instagram_handle,
         case when a.status = 'accepted' then p.youtube_handle   else null end as youtube_handle,
         case when a.status = 'accepted' then p.x_handle         else null end as x_handle
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  join public.profiles  p on p.id = a.creator_id
  where c.client_id is not null and c.client_id = public.my_client_id();

drop view if exists public.content_details;
create view public.content_details
with (security_invoker = false) as
  select ci.id, ci.campaign_id, ci.creator_id, ci.title, ci.platform,
         ci.stage, ci.due_date, ci.post_url, ci.notes, ci.updated_at, ci.created_at,
         c.title as campaign_title, c.client_id,
         p.full_name as creator_name, p.handles as creator_handles,
         p.tiktok_handle, p.instagram_handle, p.youtube_handle, p.x_handle
  from public.content_items ci
  join public.campaigns c on c.id = ci.campaign_id
  join public.profiles  p on p.id = ci.creator_id
  where public.is_admin()
     or ci.creator_id = auth.uid()
     or (c.client_id is not null and c.client_id = public.my_client_id());

grant select on public.creator_directory          to authenticated;
grant select on public.client_application_details to authenticated;
grant select on public.content_details            to authenticated;

-- =====================================================================
-- AFTER RUNNING THIS: create your own account through the portal signup
-- page, then run the two statements below to make yourself an admin.
--
--   update public.profiles set role = 'admin', status = 'approved'
--   where email = 'justin@counterpoint.marketing';
--
--   update public.profiles set role = 'admin', status = 'approved'
--   where email = 'bence@counterpoint.marketing';
-- =====================================================================
