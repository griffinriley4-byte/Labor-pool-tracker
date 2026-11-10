-- Labor Pool Tracker — Supabase schema
-- Run this once in your Supabase project's SQL Editor (Project > SQL Editor > New query).

-- ---------- Tables ----------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  role text not null check (role in ('admin','pm_gs','superintendent')),
  created_at timestamptz not null default now()
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  role text not null check (role in ('admin','pm_gs','superintendent')),
  created_at timestamptz not null default now()
);

create table if not exists public.laborers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  location text,
  hourly_rate numeric,
  last_boss_name text,
  last_boss_type text,
  status text not null default 'available',
  title text,
  speaks_english boolean not null default true,
  travel_willing boolean not null default false,
  travel_max_distance numeric,
  trades jsonb not null default '[]',
  history jsonb not null default '[]',
  reviews jsonb not null default '[]',
  notes text,
  date_added date not null default current_date,
  added_by_name text,
  crew_size integer,
  created_at timestamptz not null default now()
);

-- Safe to re-run: adds the column if this table already existed without it.
alter table public.laborers add column if not exists added_by_name text;
alter table public.laborers add column if not exists crew_size integer;

-- ---------- Helper functions (security definer so they can read profiles regardless of RLS) ----------

create or replace function public.is_authorized()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid());
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- Auto-provision a profile on signup, IF the email was invited ----------
-- If nobody invited this email, no profile row is created, so the new account
-- (which does still exist in Supabase Auth) has zero access to any app data.

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  matched_role text;
begin
  select role into matched_role from public.invites where lower(email) = lower(new.email) limit 1;
  if matched_role is not null then
    insert into public.profiles (id, name, email, role)
    values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), new.email, matched_role);
    delete from public.invites where lower(email) = lower(new.email);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Self-heal: claim a pending invite after the fact ----------
-- Handles the case where someone signed up BEFORE being invited (so the trigger
-- above found no invite at insert time), and an admin invited them afterward.
-- The client calls this after a sign-in/sign-up that comes back with no profile,
-- so the pending invite still gets claimed instead of leaving them stuck forever.

create or replace function public.claim_invite()
returns public.profiles
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  uemail text;
  uname text;
  matched_role text;
  result public.profiles;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  select email, raw_user_meta_data->>'name' into uemail, uname from auth.users where id = uid;
  select role into matched_role from public.invites where lower(email) = lower(uemail) limit 1;
  if matched_role is null then
    raise exception 'No invite found for this email';
  end if;
  insert into public.profiles (id, name, email, role)
  values (uid, coalesce(uname, split_part(uemail,'@',1)), uemail, matched_role)
  on conflict (id) do nothing;
  delete from public.invites where lower(email) = lower(uemail);
  select * into result from public.profiles where id = uid;
  return result;
end;
$$;

grant execute on function public.claim_invite() to authenticated;

-- Seed the first admin invite so whoever signs up with this email becomes Admin.
-- Change the email below if the first admin should be someone else.
insert into public.invites (email, role)
values ('griley@simpsonplastering.com', 'admin')
on conflict (email) do nothing;

-- ---------- Row Level Security ----------

alter table public.profiles enable row level security;
alter table public.invites enable row level security;
alter table public.laborers enable row level security;

-- profiles: any authorized (signed-up + invited) user can see the roster; only admins manage it
create policy "profiles_select_authorized" on public.profiles
  for select using (public.is_authorized());
create policy "profiles_update_admin" on public.profiles
  for update using (public.is_admin());
create policy "profiles_delete_admin" on public.profiles
  for delete using (public.is_admin());

-- invites: admin-only in every direction
create policy "invites_all_admin" on public.invites
  for all using (public.is_admin()) with check (public.is_admin());

-- laborers: any authorized user can read/write (matches the original app's permission model)
create policy "laborers_select_authorized" on public.laborers
  for select using (public.is_authorized());
create policy "laborers_insert_authorized" on public.laborers
  for insert with check (public.is_authorized());
create policy "laborers_update_authorized" on public.laborers
  for update using (public.is_authorized());
create policy "laborers_delete_authorized" on public.laborers
  for delete using (public.is_authorized());
