# Creator portal setup

The Supabase project is already created and connected. This file records what
was done, and what is left for you.

## What is already live

- **Supabase project:** `counterpoint-portal`, East US, free tier, under the
  `counterpoint.marketing` organization.
- **Database:** `supabase/schema.sql` has been run. Tables are `profiles`,
  `campaigns` and `applications`, all with row level security enabled.
- **Connection:** `portal/config.js` holds the project URL and the publishable
  key. That key is meant to be public. Row level security is what protects the
  data. The **secret** key is not in this repo and must never be.
- **Auth > URL Configuration:** Site URL is `https://counterpoint.marketing/portal/`
  with `https://counterpoint.marketing/portal/**` allowed as a redirect.
- **Auth > Sign In / Providers:** "Confirm email" is **off**. Supabase's built in
  mailer only allows a couple of messages per hour, so leaving it on would make
  most signups fail silently. Admin approval is the real gate: a new account can
  see nothing until you approve it. If you later want verified email addresses,
  add a real SMTP provider under Authentication > Emails and turn confirmation
  back on.

## Left to do

### 1. Make yourselves admins

1. Go to counterpoint.marketing/portal/ and sign up with your work email.
2. In the Supabase SQL editor, run:

```sql
update public.profiles set role = 'admin', status = 'approved'
where email = 'justin@counterpoint.marketing';

update public.profiles set role = 'admin', status = 'approved'
where email = 'bence@counterpoint.marketing';
```

(Bence has to sign up first before that second line matches anything.)

Reload the portal and an **Admin** link appears in the top nav.

### 2. Turn on email notifications

New signups and campaign applications are emailed to bence@counterpoint.marketing
through FormSubmit. The very first message triggers a one time confirmation:

1. Have someone sign up through the portal, or submit once yourself.
2. Bence gets a FormSubmit confirmation email. He clicks the link.
3. From then on every signup and application lands in his inbox automatically.

Until that link is clicked, notifications are held, not delivered. Everything
still saves to the database either way, so nothing is lost.

## How it works

- `portal/index.html` is sign in and apply.
- `portal/dashboard.html` is what creators see. Pending creators see a holding
  page, approved creators see open campaigns, their applications, and their own
  profile.
- `portal/admin.html` is approvals, campaign management, and applications.
  It is only reachable by accounts with `role = 'admin'`.

Campaigns have three states. **Draft** is invisible to creators, **open** is
visible and accepting applications, **closed** is hidden again. Nothing is shown
to a creator until you set it to open.

## Demographics and campaign targeting

Creators give their age, location, gender and political leaning at signup, and
can change any of it later under **My profile**. Every one of those fields is
optional, and "prefer not to say" is an explicit choice.

Campaigns carry the matching target fields: gender, age range, leaning, location
and niche. Creators see them as tags on the campaign card ("men, 20-40, lean
right, Michigan"), and a campaign that fits them is flagged **matches you** and
sorted to the top. Targeting never hides a campaign. Any approved creator can
still apply to anything, which keeps the tags useful as guidance rather than a
filter that quietly shrinks your applicant pool.

On the admin side:

- The **Creators** tab filters your roster by search text, status, gender,
  leaning and age range, with a running count of how many match.
- **Find matches** on any campaign row jumps to the Creators tab with that
  campaign's targeting already filled into the filters, narrowed to approved
  creators.
- A blank filter means "do not filter on this", so creators who declined to
  answer a question are only excluded when you actively filter on it.

If you add or rename a value, change it in three places: the check constraints
in `supabase/schema.sql`, and the `GENDERS` / `LEANINGS` lists in
`portal/app.js`. They have to agree or saving will fail.
