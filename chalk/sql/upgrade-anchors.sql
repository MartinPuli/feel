-- Room memory upgrade for a database that already ran schema.sql, seed.sql and access.sql before
-- 2026-10-17 18:00 (the anchors table came later). Paste into the Supabase SQL editor and run once.
-- New installs do not need this file: schema.sql, seed.sql and access.sql already include it all.

-- 1. Table and index (from schema.sql)
create table if not exists public.anchors (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,                          -- Supabase: auth.users.id
    venue_id text not null references public.venues (id),
    tag_id text not null check (tag_id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
    label text not null check (label = lower(btrim(label)) and length(label) between 1 and 64),
    x double precision not null check (abs(x) <= 100),
    y double precision not null check (abs(y) <= 100),
    z double precision not null check (abs(z) <= 100),
    confidence double precision not null check (confidence between 0 and 1),
    shared boolean not null default false,
    seen_at timestamptz not null default now()
);
create index if not exists anchors_by_room on public.anchors (venue_id, tag_id, label, seen_at desc) where shared;

-- 2. Demo rows (from seed.sql): the demo user's shared memory at the printed tag feel-tag-01
insert into public.anchors (id, user_id, venue_id, tag_id, label, x, y, z, confidence, shared, seen_at) values
('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -3.9, 5.2, 0.0, 0.9, true, now() - interval '4 hours'),
('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -4.1, 4.8, 0.1, 0.8, true, now() - interval '3 hours'),
('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -4.3, 5.0, -0.1, 0.7, true, now() - interval '1 day'),
('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -3.7, 5.6, 0.2, 0.95, true, now() - interval '2 hours'),
('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'water fountain', 2.0, 2.5, 0.3, 0.9, true, now() - interval '1 day'),
('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'water fountain', 2.2, 2.3, 0.3, 0.6, true, now() - interval '1 day')
on conflict (id) do nothing;

-- 3. Access (from access.sql): owners see their own anchors; Chalk reads only rows marked shared
alter table public.anchors enable row level security;
create policy "own anchors" on public.anchors for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select on public.anchors to feel_chalk;
create policy "chalk reads shared anchors" on public.anchors for select to feel_chalk using (shared);
