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

-- Access control (row-level security and the read-only role for Chalk) is in access.sql: run it once
-- after this file, with the password replaced.
