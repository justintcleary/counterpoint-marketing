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

-- ---------- Email notifications ---------------------------------------
-- All email leaves from the database, so client and creator addresses never
-- reach anyone's browser and nothing depends on a tab staying open.
--
-- Outbound mail goes through Resend. The API key lives in Supabase Vault
-- under the name resend_api_key (Dashboard > Integrations > Vault). Until it
-- is there, internal alerts to Bence fall back to FormSubmit and emails to
-- creators and clients are skipped with a warning in the Postgres logs.

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_address() returns text
language sql immutable as $$ select 'bence@counterpoint.marketing' $$;

create or replace function public.portal_url() returns text
language sql immutable as $$ select 'https://counterpoint.marketing/portal/' $$;

create or replace function public.from_address() returns text
language sql immutable as $$ select 'counterpoint.marketing <portal@counterpoint.marketing>' $$;

-- Escape user-supplied text before it goes into HTML.
create or replace function public.h(value text) returns text
language sql immutable as $$
  select replace(replace(replace(replace(coalesce(value, ''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

create or replace function public.email_html(heading text, body text, cta_label text, cta_url text)
returns text language sql immutable as $$
  select '<!doctype html><html><body style="margin:0;background:#f4f4f6;font-family:Arial,Helvetica,sans-serif;color:#0b0b0f">'
    || '<div style="max-width:560px;margin:0 auto;padding:32px 20px">'
    || '<div style="font-weight:700;font-size:18px;margin-bottom:22px">counterpoint<span style="color:#7c5cff">.marketing</span></div>'
    || '<div style="background:#ffffff;border:1px solid #e3e3ea;border-radius:12px;padding:28px">'
    || '<h1 style="font-size:22px;line-height:1.25;margin:0 0 14px">' || heading || '</h1>'
    || '<div style="font-size:15px;line-height:1.55">' || body || '</div>'
    || case when cta_url is not null then
         '<a href="' || cta_url || '" style="display:inline-block;margin-top:22px;background:#d6ff3f;color:#0b0b0f;text-decoration:none;font-weight:700;padding:12px 22px;border-radius:999px">'
         || cta_label || '</a>' else '' end
    || '</div><p style="color:#8a8a99;font-size:12px;line-height:1.5;margin-top:18px">'
    || 'Strategic influencer and digital communications. You are getting this because you have an account at counterpoint.marketing.</p>'
    || '</div></body></html>';
$$;

create or replace function public.resend_key() returns text
language plpgsql security definer stable set search_path = public, vault as $$
declare k text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  return nullif(trim(k), '');
exception when others then
  return null;
end; $$;
revoke all on function public.resend_key() from public;

-- Send one email. to_list and cc_list are comma-separated.
create or replace function public.send_email(to_list text, cc_list text, subject text, html text, plain text)
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare
  key   text := public.resend_key();
  tos   text[] := array_remove(string_to_array(replace(coalesce(to_list, ''), ' ', ''), ','), '');
  ccs   text[] := array_remove(string_to_array(replace(coalesce(cc_list, ''), ' ', ''), ','), '');
  body  jsonb;
begin
  if cardinality(tos) = 0 then return null; end if;

  if key is null then
    -- Degraded mode: only internal alerts, through FormSubmit.
    if public.notify_address() = any(tos) then
      return net.http_post(
        url     := 'https://formsubmit.co/ajax/' || public.notify_address(),
        body    := jsonb_build_object('_subject', subject, 'message', plain)
                   || case when cardinality(ccs) > 0 then jsonb_build_object('_cc', array_to_string(ccs, ',')) else '{}'::jsonb end,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Accept', 'application/json',
                                      'Origin', 'https://counterpoint.marketing',
                                      'Referer', public.portal_url()));
    end if;
    raise warning 'send_email skipped (no resend_api_key in Vault): % -> %', subject, to_list;
    return null;
  end if;

  body := jsonb_build_object(
    'from', public.from_address(), 'to', to_jsonb(tos),
    'subject', subject, 'html', html, 'text', plain);
  if cardinality(ccs) > 0 then body := body || jsonb_build_object('cc', to_jsonb(ccs)); end if;

  return net.http_post(
    url     := 'https://api.resend.com/emails',
    body    := body,
    headers := jsonb_build_object('Authorization', 'Bearer ' || key, 'Content-Type', 'application/json'));
end; $$;
revoke all on function public.send_email(text, text, text, text, text) from public;

-- Approved users of a client organization, comma-separated.
create or replace function public.client_emails(org uuid) returns text
language sql security definer stable set search_path = public as $$
  select string_agg(email, ',') from public.profiles
  where org is not null and client_id = org and role = 'client' and status = 'approved';
$$;
revoke all on function public.client_emails(uuid) from public;

create or replace function public.creator_handle_text(p public.profiles) returns text
language sql immutable as $$
  select concat_ws(', ',
    case when p.tiktok_handle    is not null then 'TikTok @'    || p.tiktok_handle    end,
    case when p.instagram_handle is not null then 'Instagram @' || p.instagram_handle end,
    case when p.youtube_handle   is not null then 'YouTube @'   || p.youtube_handle   end,
    case when p.x_handle         is not null then 'X @'         || p.x_handle         end,
    p.handles);
$$;

-- ----- new signup: tell Bence -----
create or replace function public.notify_new_profile()
returns trigger language plpgsql security definer set search_path = public as $$
declare kind text := case when new.role = 'client' then 'client account request' else 'creator application' end;
        org  text := (select name from public.clients where id = new.client_id);
        plain text;
begin
  plain := format(E'%s\nName: %s\nEmail: %s\nOrganization: %s\nHandles: %s\nAudience: %s\nInterests: %s\nLocation: %s\nNotes: %s',
    initcap(kind), coalesce(new.full_name, ''), new.email, coalesce(org, ''),
    public.creator_handle_text(new), coalesce(new.audience_size, ''),
    array_to_string(new.interests, ', '), coalesce(new.location, ''), coalesce(new.notes, ''));
  perform public.send_email(public.notify_address(), null,
    'New ' || kind || ' - ' || coalesce(new.full_name, new.email),
    public.email_html('New ' || kind,
      '<p>' || replace(public.h(plain), E'\n', '<br>') || '</p>', 'Review in admin', public.portal_url() || 'admin.html'),
    plain);
  return new;
exception when others then
  raise warning 'notify_new_profile failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created after insert on public.profiles
  for each row execute function public.notify_new_profile();

-- ----- approval: tell the person -----
create or replace function public.notify_profile_approved()
returns trigger language plpgsql security definer set search_path = public as $$
declare first text := split_part(coalesce(new.full_name, ''), ' ', 1);
        org   text := (select name from public.clients where id = new.client_id);
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    if new.role = 'client' then
      perform public.send_email(new.email, null,
        'Your counterpoint.marketing workspace is ready',
        public.email_html('You are in' || case when first <> '' then ', ' || public.h(first) else '' end || '.',
          '<p>Your workspace for <strong>' || public.h(coalesce(org, 'your organization')) || '</strong> is open. '
          || 'Brief a campaign, browse the creator roster, and follow content from draft to posted.</p>',
          'Open the client portal', public.portal_url() || 'client.html'),
        'Your workspace is open. Sign in at ' || public.portal_url());
    elsif new.role = 'creator' then
      perform public.send_email(new.email, null,
        'You are approved for the counterpoint.marketing creator network',
        public.email_html('Welcome aboard' || case when first <> '' then ', ' || public.h(first) else '' end || '.',
          '<p>Your application is approved. Open campaigns show up in your portal as they go live, with the brief, '
          || 'the rate, and who the client is looking for, and you apply to the ones that fit.</p>'
          || '<p>One thing that helps us match you: keep your profile current, especially interests, handles and audience size.</p>',
          'See open campaigns', public.portal_url() || 'dashboard.html'),
        'Your application is approved. Sign in at ' || public.portal_url());
    end if;
  end if;
  return new;
exception when others then
  raise warning 'notify_profile_approved failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_profile_approved on public.profiles;
create trigger on_profile_approved after update of status on public.profiles
  for each row execute function public.notify_profile_approved();

-- ----- new application: Bence, with the client on CC -----
create or replace function public.notify_new_application()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.campaigns%rowtype; p public.profiles%rowtype; plain text;
begin
  select * into c from public.campaigns where id = new.campaign_id;
  select * into p from public.profiles  where id = new.creator_id;
  plain := format(E'%s applied to %s%s.\n\nHandles: %s\nAudience: %s\nInterests: %s\nLocation: %s\nEmail: %s\n\nPitch:\n%s',
    coalesce(p.full_name, p.email), c.title,
    case when c.client_name <> '' then ' for ' || c.client_name else '' end,
    public.creator_handle_text(p), coalesce(p.audience_size, ''), array_to_string(p.interests, ', '),
    coalesce(p.location, ''), p.email, coalesce(new.pitch, ''));
  perform public.send_email(public.notify_address(), public.client_emails(c.client_id),
    'New application: ' || coalesce(p.full_name, 'a creator') || ' for ' || c.title,
    public.email_html(public.h(coalesce(p.full_name, 'A creator')) || ' applied to ' || public.h(c.title),
      '<p>' || replace(public.h(plain), E'\n', '<br>') || '</p>', 'Review applications', public.portal_url()),
    plain);
  return new;
exception when others then
  raise warning 'notify_new_application failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_application_created on public.applications;
create trigger on_application_created after insert on public.applications
  for each row execute function public.notify_new_application();

-- ----- application decided: tell the creator -----
create or replace function public.notify_application_decided()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.campaigns%rowtype; p public.profiles%rowtype; first text;
begin
  if new.status = old.status then return new; end if;
  select * into c from public.campaigns where id = new.campaign_id;
  select * into p from public.profiles  where id = new.creator_id;
  first := split_part(coalesce(p.full_name, ''), ' ', 1);
  if new.status = 'accepted' then
    perform public.send_email(p.email, null,
      'You are on: ' || c.title,
      public.email_html('You are signed to ' || public.h(c.title) || '.',
        '<p>' || public.h(coalesce(c.client_name, 'The client')) || ' picked you. Your deliverables are in your portal under '
        || '<strong>My content</strong>: update the stage as you go and drop the live link in when it posts. '
        || 'We will be in touch about contract and timing.</p>'
        || case when c.deadline is not null then '<p>Content deadline: <strong>' || to_char(c.deadline, 'Mon DD, YYYY') || '</strong></p>' else '' end,
        'Open my content', public.portal_url() || 'dashboard.html'),
      'You are signed to ' || c.title || '. Sign in at ' || public.portal_url());
  elsif new.status = 'declined' then
    perform public.send_email(p.email, null,
      'Update on ' || c.title,
      public.email_html('Not this one' || case when first <> '' then ', ' || public.h(first) else '' end || '.',
        '<p>Thanks for applying to <strong>' || public.h(c.title) || '</strong>. The client went another way on this campaign. '
        || 'It is not a judgment on your work: briefs are specific, and the next one may fit better. '
        || 'Keep an eye on the portal.</p>',
        'See open campaigns', public.portal_url() || 'dashboard.html'),
      'Thanks for applying to ' || c.title || '. The client went another way this time.');
  end if;
  return new;
exception when others then
  raise warning 'notify_application_decided failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_application_decided on public.applications;
create trigger on_application_decided after update of status on public.applications
  for each row execute function public.notify_application_decided();

-- ----- campaign status: client when it goes live, Bence when submitted -----
create or replace function public.notify_campaign_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare org text := (select name from public.clients where id = new.client_id);
begin
  if new.status = old.status then return new; end if;
  if new.status = 'review' then
    perform public.send_email(public.notify_address(), null,
      'Campaign submitted for review: ' || new.title,
      public.email_html(public.h(new.title) || ' is ready for review',
        '<p><strong>' || public.h(coalesce(org, new.client_name)) || '</strong> submitted a brief.</p>'
        || '<p>' || public.h(coalesce(new.summary, '')) || '</p>'
        || '<p>Budget: ' || public.h(coalesce(new.rate, 'not given')) || '<br>Deadline: '
        || coalesce(to_char(new.deadline, 'Mon DD, YYYY'), 'not set') || '</p>'
        || '<p style="white-space:pre-wrap">' || public.h(coalesce(new.brief, '')) || '</p>',
        'Open in admin', public.portal_url() || 'admin.html'),
      format(E'%s submitted "%s" for review.\n\n%s', coalesce(org, new.client_name), new.title, coalesce(new.brief, '')));
  elsif new.status = 'open' and new.client_id is not null then
    perform public.send_email(public.client_emails(new.client_id), null,
      'Your campaign is live: ' || new.title,
      public.email_html(public.h(new.title) || ' is live with creators.',
        '<p>Approved creators can now see the brief and apply. You will get a copy of each application as it comes in, '
        || 'and we will line up the right people from there.</p>',
        'Open the client portal', public.portal_url() || 'client.html'),
      new.title || ' is now live with creators. Sign in at ' || public.portal_url());
  end if;
  return new;
exception when others then
  raise warning 'notify_campaign_status failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_campaign_status on public.campaigns;
create trigger on_campaign_status after update of status on public.campaigns
  for each row execute function public.notify_campaign_status();

-- ----- content stage: review requests to the client, decisions to the creator -----
create or replace function public.notify_content_stage()
returns trigger language plpgsql security definer set search_path = public as $$
declare c public.campaigns%rowtype; p public.profiles%rowtype; item text;
begin
  if new.stage = old.stage then return new; end if;
  select * into c from public.campaigns where id = new.campaign_id;
  select * into p from public.profiles  where id = new.creator_id;
  item := coalesce(new.title, 'A deliverable');

  if new.stage = 'submitted for review' then
    perform public.send_email(
      coalesce(public.client_emails(c.client_id), public.notify_address()),
      case when c.client_id is not null then public.notify_address() end,
      'Ready for your review: ' || item || ' (' || c.title || ')',
      public.email_html('Content is waiting for your review.',
        '<p><strong>' || public.h(coalesce(p.full_name, 'A creator')) || '</strong> submitted <strong>' || public.h(item)
        || '</strong> for <strong>' || public.h(c.title) || '</strong>.</p>'
        || case when new.post_url is not null then '<p><a href="' || public.h(new.post_url) || '">' || public.h(new.post_url) || '</a></p>' else '' end
        || case when new.notes is not null then '<p style="white-space:pre-wrap">' || public.h(new.notes) || '</p>' else '' end
        || '<p>Approve it, or send it back with a note, from the Content tab.</p>',
        'Review it', public.portal_url() || 'client.html'),
      coalesce(p.full_name, 'A creator') || ' submitted ' || item || ' for ' || c.title || '. Review at ' || public.portal_url());
  elsif new.stage = 'changes requested' then
    perform public.send_email(p.email, public.notify_address(),
      'Changes requested: ' || item || ' (' || c.title || ')',
      public.email_html('A quick revision on ' || public.h(item) || '.',
        '<p>The client sent <strong>' || public.h(item) || '</strong> for <strong>' || public.h(c.title) || '</strong> back with notes:</p>'
        || '<p style="white-space:pre-wrap;background:#f4f4f6;padding:12px;border-radius:8px">' || public.h(coalesce(new.notes, '')) || '</p>'
        || '<p>Make the change, then set the stage back to submitted for review.</p>',
        'Open my content', public.portal_url() || 'dashboard.html'),
      'Changes requested on ' || item || ': ' || coalesce(new.notes, ''));
  elsif new.stage = 'approved' then
    perform public.send_email(p.email, null,
      'Approved: ' || item || ' (' || c.title || ')',
      public.email_html(public.h(item) || ' is approved.',
        '<p>The client signed off on your <strong>' || public.h(item) || '</strong> for <strong>' || public.h(c.title) || '</strong>. '
        || 'Schedule it, post it, and paste the live link into your portal so everyone can see it land.</p>',
        'Open my content', public.portal_url() || 'dashboard.html'),
      item || ' for ' || c.title || ' is approved. Post it and add the link at ' || public.portal_url());
  elsif new.stage = 'posted' then
    perform public.send_email(
      coalesce(public.client_emails(c.client_id), public.notify_address()),
      case when c.client_id is not null then public.notify_address() end,
      'Posted: ' || item || ' (' || c.title || ')',
      public.email_html(public.h(item) || ' is live.',
        '<p><strong>' || public.h(coalesce(p.full_name, 'A creator')) || '</strong> posted <strong>' || public.h(item) || '</strong> for <strong>' || public.h(c.title) || '</strong>.</p>'
        || case when new.post_url is not null then '<p><a href="' || public.h(new.post_url) || '">' || public.h(new.post_url) || '</a></p>' else '' end,
        'See the campaign', public.portal_url() || 'client.html'),
      item || ' for ' || c.title || ' is posted. ' || coalesce(new.post_url, ''));
  end if;
  return new;
exception when others then
  raise warning 'notify_content_stage failed: %', sqlerrm; return new;
end; $$;

drop trigger if exists on_content_stage on public.content_items;
create trigger on_content_stage after update of stage on public.content_items
  for each row execute function public.notify_content_stage();

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
