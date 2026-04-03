-- Sweeply — initial schema
-- Safe to re-run: all statements are idempotent.

-- ── Profiles (1:1 with auth.users) ──────────────────────────────────────────
create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  full_name       text,
  business_name   text,
  email           text,
  phone           text,
  updated_at      timestamptz default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Users read own profile"   on public.profiles;
drop policy if exists "Users insert own profile" on public.profiles;
drop policy if exists "Users update own profile" on public.profiles;

create policy "Users read own profile"
  on public.profiles for select using (auth.uid() = id);

create policy "Users insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

create policy "Users update own profile"
  on public.profiles for update using (auth.uid() = id);

-- ── Clients ──────────────────────────────────────────────────────────────────
create table if not exists public.clients (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references auth.users (id) on delete cascade,
  name                 text not null,
  email                text default '',
  phone                text default '',
  address              text default '',
  city                 text default '',
  state                text default '',
  zip                  text default '',
  preferred_service    text,
  entry_instructions   text default '',
  notes                text default '',
  created_at           timestamptz default now()
);

create index if not exists clients_user_id_idx on public.clients (user_id);
alter table public.clients enable row level security;

drop policy if exists "Users manage own clients" on public.clients;
create policy "Users manage own clients"
  on public.clients for all
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── Jobs ─────────────────────────────────────────────────────────────────────
-- service_type / status values must match Swift ServiceType / JobStatus rawValues
create table if not exists public.jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  client_id       uuid not null references public.clients (id) on delete cascade,
  client_name     text not null,
  service_type    text not null,
  scheduled_at    timestamptz not null,
  duration_hours  double precision not null default 2,
  price           double precision not null default 0,
  status          text not null,
  address         text default '',
  is_recurring    boolean default false,
  created_at      timestamptz default now()
);

create index if not exists jobs_user_id_idx on public.jobs (user_id);
alter table public.jobs enable row level security;

drop policy if exists "Users manage own jobs" on public.jobs;
create policy "Users manage own jobs"
  on public.jobs for all
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── Invoices ─────────────────────────────────────────────────────────────────
create table if not exists public.invoices (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  client_id       uuid not null references public.clients (id) on delete cascade,
  client_name     text not null,
  amount          double precision not null,
  status          text not null,
  created_at      timestamptz not null default now(),
  due_date        timestamptz not null,
  invoice_number  text not null
);

create index if not exists invoices_user_id_idx on public.invoices (user_id);
alter table public.invoices enable row level security;

drop policy if exists "Users manage own invoices" on public.invoices;
create policy "Users manage own invoices"
  on public.invoices for all
  using      (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── Auto-create profile on sign-up ───────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
