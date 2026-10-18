-- Journey upgrade for a database that already ran schema.sql, seed.sql and access.sql (and, if it predates room structure,
-- upgrade-room-maps.sql) before 2026-10-18 (the journeys table came later). Paste into the Supabase SQL editor and run
-- once. New installs do not need this file: schema.sql, seed.sql and access.sql already include it all.

-- 1. Table and index (from schema.sql): one walk from a printed tag toward a remembered target, in the tag's levelled
--    frame (chalk/feel_chalk/journeys.py; protocol/journey-v1.json is the shared vector).
create table if not exists public.journeys (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,                          -- Supabase: auth.users.id
    venue_id text not null references public.venues (id),
    tag_id text not null check (tag_id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
    session_id text not null check (length(session_id) between 1 and 64),
    target_label text not null check (target_label = lower(btrim(target_label)) and length(target_label) between 1 and 64),
    started_at timestamptz not null default now(),
    arrived_at timestamptz,
    arrival_distance_m double precision not null check (arrival_distance_m >= 0 and arrival_distance_m <= 200),
    steps jsonb not null default '[]',
    obstacles jsonb not null default '[]',
    cue_latency_ms jsonb not null default '[]',
    shared boolean not null default false,
    check (jsonb_typeof(steps) = 'array' and jsonb_typeof(obstacles) = 'array' and jsonb_typeof(cue_latency_ms) = 'array'),
    check (arrived_at is null or arrived_at >= started_at)
);
create index if not exists journeys_by_room on public.journeys (venue_id, tag_id, started_at desc) where shared;

-- 2. Demo rows (from seed.sql): the demo user's three shared journeys to the remembered exit at feel-tag-01
--    (the journeys of protocol/journey-v1.json: two arrived, one stopped short)
insert into public.journeys (id, user_id, venue_id, tag_id, session_id, target_label, started_at, arrived_at, arrival_distance_m, steps, obstacles, cue_latency_ms, shared) values
('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'seed-session-01', 'exit',
 now() - interval '3 days', now() - interval '3 days' + interval '14 seconds', 0.0,
 '[{"t": 0, "x": -1.0, "y": 1.1, "heading_deg": 0}, {"t": 2, "x": -1.0, "y": 2.1, "heading_deg": 0}, {"t": 4, "x": -1.0, "y": 3.1, "heading_deg": 0}, {"t": 6, "x": -1.0, "y": 4.1, "heading_deg": 0}, {"t": 8, "x": -1.0, "y": 5.1, "heading_deg": 270}, {"t": 10, "x": -2.0, "y": 5.1, "heading_deg": 270}, {"t": 12, "x": -3.0, "y": 5.1, "heading_deg": 270}, {"t": 14, "x": -4.0, "y": 5.1, "heading_deg": 270}]',
 '[{"x": -2.05, "y": 4.05}]', '[120, 95, 140, 110, 400]', true),
('40000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'seed-session-02', 'exit',
 now() - interval '2 days', now() - interval '2 days' + interval '10 seconds', 0.0,
 '[{"t": 0, "x": -1.0, "y": 1.1, "heading_deg": 323.1}, {"t": 2, "x": -1.6, "y": 1.9, "heading_deg": 323.1}, {"t": 4, "x": -2.2, "y": 2.7, "heading_deg": 323.1}, {"t": 6, "x": -2.8, "y": 3.5, "heading_deg": 323.1}, {"t": 8, "x": -3.4, "y": 4.3, "heading_deg": 323.1}, {"t": 10, "x": -4.0, "y": 5.1, "heading_deg": 323.1}]',
 '[{"x": -2.25, "y": 2.85}]', '[90, 100, 110, 130]', true),
('40000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'seed-session-03', 'exit',
 now() - interval '1 day', null, 3.606,
 '[{"t": 0, "x": -1.0, "y": 1.1, "heading_deg": 0}, {"t": 2, "x": -1.0, "y": 2.1, "heading_deg": 0}, {"t": 4, "x": -1.0, "y": 3.1, "heading_deg": 0}]',
 '[{"x": -1.05, "y": 3.55}]', '[150, 160]', true)
on conflict (id) do nothing;

-- 3. Access (from access.sql): owners see their own journeys; Chalk reads only rows marked shared
alter table public.journeys enable row level security;
create policy "own journeys" on public.journeys for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select on public.journeys to feel_chalk;
create policy "chalk reads shared journeys" on public.journeys for select to feel_chalk using (shared);
