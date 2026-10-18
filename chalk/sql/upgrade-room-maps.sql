-- Room structure upgrade for a database that already ran schema.sql, seed.sql and access.sql (and, if it predates room
-- memory, upgrade-anchors.sql) before 2026-10-18 (the room_maps table came later). Paste into the Supabase SQL editor
-- and run once. New installs do not need this file: schema.sql, seed.sql and access.sql already include it all.

-- 1. Table and index (from schema.sql): one visit's structural map of the room behind a printed tag, as cells
--    (unknown, free or blocked) in the tag's levelled frame, run-length encoded (chalk/feel_chalk/room_map.py).
create table if not exists public.room_maps (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,                          -- Supabase: auth.users.id
    venue_id text not null references public.venues (id),
    tag_id text not null check (tag_id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
    cell_size double precision not null check (cell_size > 0 and cell_size <= 1),
    origin_x double precision not null check (abs(origin_x) <= 100),
    origin_y double precision not null check (abs(origin_y) <= 100),
    width integer not null check (width between 1 and 2000),
    height integer not null check (height between 1 and 2000),
    cells text not null check (cells ~ '^([1-9][0-9]*[ufb])+$'),
    shared boolean not null default false,
    seen_at timestamptz not null default now(),
    check (width * height <= 250000)
);
create index if not exists room_maps_by_room on public.room_maps (venue_id, tag_id, seen_at desc) where shared;

-- 2. Demo rows (from seed.sql): the demo user's three shared visits at the printed tag feel-tag-01
--    (the visit maps of protocol/room-map-v1.json; merged they give the 8 x 6 map "28f2b10f2u6b")
insert into public.room_maps (id, user_id, venue_id, tag_id, cell_size, origin_x, origin_y, width, height, cells, shared, seen_at) values
('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, 0.0, 0.0, 6, 6, '14f2b4f2b8f6b', true, now() - interval '3 days'),
('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, -0.2, 0.0, 8, 6, '40f2u6b', true, now() - interval '1 day'),
('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, 0.1, 0.1, 4, 5, '9f1u1b5f4b', true, now() - interval '2 hours')
on conflict (id) do nothing;

-- 3. Access (from access.sql): owners see their own visits; Chalk reads only rows marked shared
alter table public.room_maps enable row level security;
create policy "own room maps" on public.room_maps for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select on public.room_maps to feel_chalk;
create policy "chalk reads shared room maps" on public.room_maps for select to feel_chalk using (shared);
