-- Run once after schema.sql, in the Supabase SQL editor, with the password replaced.
-- 1. Row-level security: a signed-in phone (publishable key + user JWT) sees and writes only its
--    own finds; venue rows are readable by everyone.
alter table public.confirmed_finds enable row level security;
create policy "own finds" on public.confirmed_finds for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
alter table public.anchors enable row level security;
create policy "own anchors" on public.anchors for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
alter table public.room_maps enable row level security;
create policy "own room maps" on public.room_maps for all
    using (auth.uid() = user_id) with check (auth.uid() = user_id);
alter table public.venues enable row level security;
create policy "venues are public" on public.venues for select using (true);
alter table public.venue_entries enable row level security;
create policy "venue entries are public" on public.venue_entries for select using (true);

-- 2. Chalk's read-only role. Row-level security applies to it as well (only superusers and
--    BYPASSRLS roles skip it, and Supabase grants neither), so it gets its own select policies.
--    Give the Chalk data source this role as user "feel_chalk.<project ref>" on the session pooler.
create role feel_chalk login password 'REPLACE-WITH-A-GENERATED-PASSWORD';
grant usage on schema public to feel_chalk;
grant select on public.confirmed_finds, public.anchors, public.room_maps, public.venues, public.venue_entries to feel_chalk;
create policy "chalk reads finds" on public.confirmed_finds for select to feel_chalk using (true);
-- Room memory is opt-in: Chalk sees an anchor or a visit's map only when its owner set shared = true.
create policy "chalk reads shared anchors" on public.anchors for select to feel_chalk using (shared);
create policy "chalk reads shared room maps" on public.room_maps for select to feel_chalk using (shared);
create policy "chalk reads venues" on public.venues for select to feel_chalk using (true);
create policy "chalk reads venue entries" on public.venue_entries for select to feel_chalk using (true);
