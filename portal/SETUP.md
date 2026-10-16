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

### 1. Approve client accounts as they come in

When someone signs up as a brand, they appear under the admin **Clients** tab
as pending with their organization already attached. Approve them there. If two
people from one company spelled the name differently, reassign one of them to
the other organization with the dropdown before approving.

### 2. Make yourselves admins

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

### 3. Turn on email notifications

New signups, campaign applications, client briefs submitted for review, and
change requests on content are all emailed to bence@counterpoint.marketing
through FormSubmit. The very first message triggers a one time confirmation:

1. Have someone sign up through the portal, or submit once yourself.
2. Bence gets a FormSubmit confirmation email. He clicks the link.
3. From then on every signup and application lands in his inbox automatically.

Until that link is clicked, notifications are held, not delivered. Everything
still saves to the database either way, so nothing is lost.

## How it works

Three kinds of account, all in `profiles.role`:

- **creator** applies to campaigns and delivers content. Lives in
  `portal/dashboard.html`: open campaigns, their applications, their content
  tracker, their profile.
- **client** is a brand or organization. Lives in `portal/client.html`: brief
  campaigns, see applicants, browse the creator roster, approve or send back
  content. People sign up as a client by picking "I'm a brand or organization"
  on the signup page (`portal/#client` opens it directly). Two people who give
  the same organization name share one workspace.
- **admin** is counterpoint. `portal/admin.html` approves creators and clients,
  runs campaigns, places creators, and manages every deliverable.

`portal/index.html` is the shared sign in and sign up page. After signing in,
everyone is routed to their own page.

### Campaign states

- **draft**: only the owner sees it. A client works on the brief here.
- **review**: the client submitted it. Counterpoint gets an email, reviews the
  brief, and sets it to open when creators should see it. Clients cannot open a
  campaign themselves: who sees a brief and who gets signed is our call.
- **open**: approved creators can see it and apply.
- **closed**: finished or withdrawn.

### Content tracking

Accepting an application signs the creator and automatically creates one
deliverable in `content_items` for them, prefilled from the campaign's
deliverables, platforms and deadline. Add more by hand from the admin Content
tab when a creator owes several pieces.

Each deliverable moves through: not started, drafting, submitted for review,
changes requested, approved, scheduled, posted.

- Creators set the stage themselves (except approved and changes requested),
  attach the live link, and leave notes.
- Clients see everything on their campaigns with a progress bar per campaign.
  When something is submitted for review they can **Approve** or **Request
  changes** with a note. A change request emails counterpoint and shows up for
  the creator in red.
- Admins can edit every field, including stage, on every deliverable.

### What clients can and cannot see

The creator roster is counterpoint's asset. Clients browse approved creators
with name, niche, audience size, and demographics, but never email addresses,
and handles only for creators already accepted onto one of their campaigns.
That is enforced in the database, not just hidden in the page: clients have no
read access to `profiles` at all and go through the `creator_directory`,
`client_application_details` and `content_details` views instead.

## Interests

Creators pick up to five interest tags (`profiles.interests`, a text array
capped at five in the database). Signup and My profile use a chip editor with
a suggestion list from `INTEREST_SUGGESTIONS` in `portal/app.js`, but any word
is allowed, lowercased. Admins and clients filter the roster by interest, and
Find matches carries a campaign's niche into that filter. The old free-text
`niche` column was split on commas into tags once, and is kept only as a
fallback display for anyone with no tags.

## Social handles

Handles are stored one column per platform: `tiktok_handle`,
`instagram_handle`, `youtube_handle`, `x_handle`, plus the free-text `handles`
column for anything else (Twitch, Substack, and so on). Creators can paste
"@name", "name" or a full profile URL and it is normalized to the bare name.
Everywhere handles are shown they render as links to the profile. Accounts
created before this change still have their original text in the "other"
field; creators can move it into the right boxes under My profile.

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
