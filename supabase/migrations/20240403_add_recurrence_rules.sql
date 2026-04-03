-- Add recurrence_rules table to manage repeating jobs and link them back to a rule.
create table if not exists public.recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id uuid not null references public.clients (id) on delete cascade,
  service_type text not null,
  frequency text not null, -- once, weekly, biweekly, monthly, custom
  interval_days integer default 7,
  start_date timestamptz not null,
  end_date timestamptz,
  price double precision not null,
  duration_hours double precision not null,
  created_at timestamptz default now()
);

alter table public.recurrence_rules enable row level security;

create policy "Users manage own recurrence rules"
  on public.recurrence_rules for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Link jobs to their parent recurrence rule
alter table public.jobs add column if not exists recurrence_rule_id uuid references public.recurrence_rules (id) on delete set null;
create index if not exists jobs_recurrence_rule_id_idx on public.jobs (recurrence_rule_id);
