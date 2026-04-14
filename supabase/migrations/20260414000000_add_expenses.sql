create table if not exists public.expenses (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    amount      numeric(10, 2) not null,
    category    text not null default 'other',
    notes       text not null default '',
    date        date not null default current_date
);

create index if not exists expenses_user_id_idx on public.expenses (user_id);
alter table public.expenses enable row level security;

drop policy if exists "Users manage their own expenses" on public.expenses;
create policy "Users manage their own expenses"
    on public.expenses for all
    using      (auth.uid() = user_id)
    with check (auth.uid() = user_id);
