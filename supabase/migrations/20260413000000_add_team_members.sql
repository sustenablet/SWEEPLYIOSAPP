create table if not exists public.team_members (
    id         uuid primary key default gen_random_uuid(),
    owner_id   uuid not null references auth.users (id) on delete cascade,
    name       text not null,
    email      text not null,
    role       text not null default 'member',
    status     text not null default 'invited',
    added_at   timestamptz not null default now()
);

create index if not exists team_members_owner_id_idx on public.team_members (owner_id);
alter table public.team_members enable row level security;

drop policy if exists "Owners manage their team" on public.team_members;
create policy "Owners manage their team"
    on public.team_members for all
    using      (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);
