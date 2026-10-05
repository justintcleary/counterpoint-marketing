-- =====================================================================
-- counterpoint.marketing creator portal
-- Run this in Supabase: Dashboard > SQL Editor > New query > Run.
-- Safe to re-run: every statement is idempotent.
-- =====================================================================

-- ---------- Tables ----------------------------------------------------

create table if not exists public.profiles (
  id                uuid primary key references auth.users on delete cascade,
  email             text not null,
  full_name         text,
  handles           text,
  audience_size     text,
  niche             text,
  location          text,
  age               int,
  gender            text,
  political_leaning text,
  notes             text,
  status            text not null default 'pending'
                    check (status in ('pending','approved','rejected')),
  role              text not null default 'creator'
                    check (role in ('creator','admin')),
  created_at        timestamptz not null default now()
);

create table if not exists public.campaigns (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  client_name     text,
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
  status          text not null default 'draft'
                  check (status in ('draft','open','closed')),
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

create index if not exists applications_campaign_idx on public.applications(campaign_id);
create index if not exists applications_creator_idx  on public.applications(creator_id);

-- ---------- Migrations for projects created before demographics -------

alter table public.profiles  add column if not exists age               int;
alter table public.profiles  add column if not exists gender            text;
alter table public.profiles  add column if not exists political_leaning text;

alter table public.campaigns add column if not exists target_gender   text default 'any';
alter table public.campaigns add column if not exists target_age_min  int;
alter table public.campaigns add column if not exists target_age_max  int;
alter table public.campaigns add column if not exists target_leaning  text default 'any';
alter table public.campaigns add column if not exists target_location text;
alter table public.campaigns add column if not exists target_niche    text;

-- Controlled vocabularies. Creators may always decline to answer, so the
-- columns stay nullable and carry an explicit "prefer not to say" value.
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

alter table public.campaigns drop constraint if exists campaigns_target_gender_check;
alter table public.campaigns add  constraint campaigns_target_gender_check
  check (target_gender is null or target_gender in
    ('any','woman','man','non-binary'));

alter table public.campaigns drop constraint if exists campaigns_target_leaning_check;
alter table public.campaigns add  constraint campaigns_target_leaning_check
  check (target_leaning is null or target_leaning in
    ('any','left','lean left','moderate','lean right','right','non-political'));

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
                 where id = auth.uid() and status = 'approved');
$$;

-- ---------- Auto-create a profile when someone signs up ---------------

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (
    id, email, full_name, handles, audience_size, niche, location,
    age, gender, political_leaning, notes)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'handles',
    new.raw_user_meta_data->>'audience_size',
    new.raw_user_meta_data->>'niche',
    new.raw_user_meta_data->>'location',
    nullif(new.raw_user_meta_data->>'age','')::int,
    nullif(new.raw_user_meta_data->>'gender',''),
    nullif(new.raw_user_meta_data->>'political_leaning',''),
    new.raw_user_meta_data->>'notes'
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Row level security ----------------------------------------

alter table public.profiles     enable row level security;
alter table public.campaigns    enable row level security;
alter table public.applications enable row level security;

-- profiles: you can read and edit your own row; admins can do anything
drop policy if exists profiles_select_own   on public.profiles;
drop policy if exists profiles_update_own   on public.profiles;
drop policy if exists profiles_admin_all    on public.profiles;

create policy profiles_select_own on public.profiles
  for select using (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid() and status = (select status from public.profiles where id = auth.uid())
                               and role   = (select role   from public.profiles where id = auth.uid()));

create policy profiles_admin_all on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- campaigns: approved creators see open campaigns; admins do anything
drop policy if exists campaigns_select_open on public.campaigns;
drop policy if exists campaigns_admin_all   on public.campaigns;

create policy campaigns_select_open on public.campaigns
  for select using (status = 'open' and public.is_approved());

create policy campaigns_admin_all on public.campaigns
  for all using (public.is_admin()) with check (public.is_admin());

-- applications: approved creators manage their own; admins do anything
drop policy if exists applications_select_own on public.applications;
drop policy if exists applications_insert_own on public.applications;
drop policy if exists applications_admin_all  on public.applications;

create policy applications_select_own on public.applications
  for select using (creator_id = auth.uid());

create policy applications_insert_own on public.applications
  for insert with check (
    creator_id = auth.uid()
    and public.is_approved()
    and exists (select 1 from public.campaigns c where c.id = campaign_id and c.status = 'open')
  );

create policy applications_admin_all on public.applications
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------- Admin view: applications joined to people and campaigns ----

drop view if exists public.application_details;
create view public.application_details
with (security_invoker = true) as
  select a.id, a.status, a.pitch, a.created_at,
         c.id as campaign_id, c.title as campaign_title, c.client_name,
         p.id as creator_id, p.full_name, p.email, p.handles, p.audience_size,
         p.niche, p.location, p.age, p.gender, p.political_leaning
  from public.applications a
  join public.campaigns c on c.id = a.campaign_id
  join public.profiles  p on p.id = a.creator_id;

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
