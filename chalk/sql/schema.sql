-- FEEL context database: the Supabase project's Postgres (SUPABASE_URL in chalk/.env is its API address; Chalk
-- connects to the database itself, see chalk/feel_context/README.md).
-- The phone writes confirmed finds here; Chalk reads every table through the "feel_finds"
-- PostgreSQL data source (chalk/feel_context/sources.py). Written for Supabase, works on plain Postgres.

create extension if not exists pgcrypto;

-- One row each time the user confirms a find ("found it") after Where-is or a finder pointed at something.
create table if not exists public.confirmed_finds (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,                          -- Supabase: auth.users.id
    object_name text not null check (object_name = lower(btrim(object_name)) and length(object_name) between 1 and 64),
    place text not null check (length(btrim(place)) between 1 and 200),
    confidence double precision not null check (confidence between 0 and 1),
    found_at timestamptz not null default now()
);
create index if not exists confirmed_finds_history on public.confirmed_finds (user_id, object_name, found_at desc);

-- Reviewed venue information. Rows come from reviewed official sources only; FEEL repeats them verbatim.
create table if not exists public.venues (
    id text primary key check (length(id) between 1 and 64),
    name text not null check (length(name) between 1 and 120)
);
create table if not exists public.venue_entries (
    id text primary key check (length(id) between 1 and 64),
    venue_id text not null references public.venues (id),
    kind text not null check (kind in ('place', 'restriction')),
    name text not null check (length(name) between 1 and 120),
    aliases text[] not null default '{}',
    text text not null check (length(text) between 1 and 500),
    source_url text not null check (source_url like 'https://%'),
    retrieved_at timestamptz not null,
    effective_from timestamptz,
    effective_until timestamptz,
    applies_to text references public.venue_entries (id),
    check (effective_from is null or effective_until is null or effective_from < effective_until),
    check (kind <> 'restriction' or (applies_to is not null and effective_from is not null))
);
create index if not exists venue_entries_by_venue on public.venue_entries (venue_id);

-- One remembered sighting of a target, in the frame of the printed FEEL room tag that was in view when the user
-- confirmed it ("found it", or reaching a Where-is target). The frame is ARKit's image anchor for the tag:
-- x right along the tag, y out of the tag into the room, z down along the tag, in metres. Anchors are personal
-- data: a row leaves its owner's phone for the room's shared memory only when they set shared = true.
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

-- One visit's structural map of the room behind a printed tag: the floor grid the phone's route planner learned, as
-- cells (unknown, free or blocked) of cell_size metres in the tag's levelled frame (x right along the tag, y out into the
-- room; origin_x, origin_y is the corner of the cell with the smallest indices), run-length encoded row by row as
-- <count><state> with u, f and b (chalk/feel_chalk/room_map.py). Chalk merges the shared visits of a room by a per-cell
-- vote. Like anchors, a row leaves its owner's phone for the shared memory only when they set shared = true.
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

-- Access control (row-level security and the read-only role for Chalk) is in access.sql: run it once
-- after this file, with the password replaced.
