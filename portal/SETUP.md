# Creator portal setup

Three steps, about 15 minutes total. You only do this once.

## 1. Create the Supabase project

1. Go to supabase.com and sign up (free tier is fine).
2. Create a new project. Pick any name, set a database password, choose a US region.
3. Wait for it to finish provisioning (about two minutes).

## 2. Create the database

1. In Supabase, open **SQL Editor** in the left sidebar.
2. Click **New query**.
3. Open `supabase/schema.sql` from this repo, copy the whole file, paste it in, click **Run**.

You should see "Success. No rows returned."

## 3. Connect the portal

1. In Supabase go to **Project Settings > Data API**.
2. Copy the **Project URL** and the **anon public** key.
3. Open `portal/config.js` and paste them in:

```js
export const SUPABASE_URL = "https://xxxxxxxx.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGci...";
```

The anon key is meant to be public. Row level security in the schema is what
protects the data. Never paste the `service_role` key anywhere in this repo.

4. Commit and push. The portal goes live at counterpoint.marketing/portal/

## 4. Make yourself an admin

1. Go to counterpoint.marketing/portal/ and sign up with your work email.
2. Back in the Supabase SQL editor, run:

```sql
update public.profiles set role = 'admin', status = 'approved'
where email = 'justin@counterpoint.marketing';

update public.profiles set role = 'admin', status = 'approved'
where email = 'bence@counterpoint.marketing';
```

(Bence has to sign up first before that second line will match anything.)

Reload the portal and an **Admin** link appears in the top nav.

## 5. Turn on email notifications

New signups and campaign applications are emailed to bence@counterpoint.marketing
through FormSubmit. The very first message triggers a one time confirmation:

1. Have someone sign up through the portal, or submit once yourself.
2. Bence gets a FormSubmit confirmation email. He clicks the link.
3. From then on every signup and application lands in his inbox automatically.

Until that link is clicked, notifications are held, not delivered. Everything
still saves to the database either way, so nothing is lost.

## Settings worth checking in Supabase

- **Authentication > Providers > Email**: confirm "Confirm email" is ON so people
  verify their address. Supabase sends those emails for you.
- **Authentication > URL Configuration**: set Site URL to
  `https://counterpoint.marketing/portal/` so confirmation links come back to the
  right place.

## How it works

- `portal/index.html` is sign in and apply.
- `portal/dashboard.html` is what creators see. Pending creators see a holding
  page, approved creators see open campaigns and can apply.
- `portal/admin.html` is approvals, campaign management, and applications.
  It is only reachable by accounts with `role = 'admin'`.

Campaigns have three states. **Draft** is invisible to creators, **open** is
visible and accepting applications, **closed** is hidden again. Nothing is shown
to a creator until you set it to open.
