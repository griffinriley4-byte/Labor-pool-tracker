# Labor Pool Tracker

Internal laborer roster & dashboard for Simpson Plastering. Static HTML/JS front end backed by Supabase (Postgres + Auth), deployed on Vercel from this GitHub repo.

## Setup (one-time)

### 1. Supabase

1. Create a project at supabase.com (any region/plan is fine for this app's size).
2. Open **SQL Editor > New query**, paste in the contents of [schema.sql](schema.sql), and run it.
   - This creates the `laborers`, `profiles`, and `invites` tables, sets up Row Level Security, and seeds an admin invite for `griley@simpsonplastering.com`. Edit that email in the script first if the first admin should be someone else.
3. Go to **Authentication > Providers > Email** and turn **off** "Confirm email" — this is an internal tool, so accounts should be usable immediately after sign-up instead of waiting on a confirmation email.
4. Go to **Project Settings > API** and copy the **Project URL** and the **anon public** key.
5. Paste those two values into [config.js](config.js) in this repo (replacing the placeholders), commit, and push.

### 2. Vercel

1. Import this GitHub repo into Vercel ("Add New... > Project").
2. Framework preset: **Other** (it's a static site, no build step needed).
3. Deploy. Every push to `main` redeploys automatically.

### 3. First sign-in

Whoever's email was seeded in `schema.sql` (default `griley@simpsonplastering.com`) should open the deployed site and use **Create an account** with that email — they'll automatically become Admin. From there, use the **Access** tab to invite everyone else by email and role.

## How access works

- Signing in requires a Supabase Auth account **and** a matching row in the `profiles` table.
- New accounts only get a `profiles` row (i.e. only get real access) if an admin invited that email first, via the Access tab.
- "Revoke access" in the Access tab removes app access (deletes the `profiles` row) but does not delete the underlying Supabase Auth login — do that from the Supabase dashboard (Authentication > Users) if someone should be fully removed.
- The Supabase anon key in `config.js` is meant to be public; actual data access is enforced by the Row Level Security policies in `schema.sql`, not by keeping that key secret.
