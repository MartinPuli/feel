-- Demo rows for chalk/feel_context: the reviewed Harvard Yard entries (protocol/harvard-yard-source.json),
-- three confirmed finds for one demo user, that user's shared room memory at the printed tag feel-tag-01, and three
-- shared visits of the room's structure behind it. Run after schema.sql; safe to run twice.

insert into public.venues (id, name) values ('harvard-yard', 'Harvard Yard')
on conflict (id) do update set name = excluded.name;

insert into public.venue_entries (id, venue_id, kind, name, aliases, text, source_url, retrieved_at, effective_from, effective_until, applies_to) values
('harvard-yard-gates', 'harvard-yard', 'place', 'Harvard Yard gates',
 '{"harvard yard","the yard","yard entrance","yard gates"}',
 'Johnston, Meyer, Sever, Solomon/Lamont, Thayer, Wadsworth and Widener gates are open 24 hours. Other listed gates are open 6 AM to 7 PM. From 9 PM tonight until 5 AM, and Sunday from 9 PM until midnight, entry is only through the Johnston, Sever, Widener and Meyer gates, with a Harvard ID and one guest.',
 'https://accessibility.harvard.edu/campus-access', '2026-10-17T20:00:00Z', null, null, null),
('disability-resources', 'harvard-yard', 'place', 'University Disability Resources',
 '{"disability resources","accessibility office"}',
 'Richard A. and Susan F. Smith Campus Center, Suite 900. Phone 617-495-1859.',
 'https://accessibility.harvard.edu/campus-access', '2026-10-17T20:00:00Z', null, null, null),
('accessible-campus-map', 'harvard-yard', 'place', 'Accessible campus map',
 '{"accessible entrance","accessible entrances","campus map"}',
 'The campus access page links an interactive map of accessible pathways and building entrances for Cambridge and Allston, and a PDF map for the Longwood campus.',
 'https://accessibility.harvard.edu/campus-access', '2026-10-17T20:00:00Z', null, null, null),
('yard-weekend-restriction', 'harvard-yard', 'restriction', 'Yard weekend restriction', '{}',
 'Until midnight Monday, entry from 9 PM to 5 AM, and Sunday from 9 PM to midnight, is only through the Johnston, Sever, Widener and Meyer gates. Those gates are staffed. Entry needs a Harvard ID, and students may bring one guest.',
 'https://accessibility.harvard.edu/campus-access', '2026-10-17T20:00:00Z', '2026-10-18T01:00:00Z', '2026-10-19T04:00:00Z', 'harvard-yard-gates')
on conflict (id) do update set text = excluded.text, aliases = excluded.aliases, retrieved_at = excluded.retrieved_at,
    effective_from = excluded.effective_from, effective_until = excluded.effective_until;

-- Demo user 00000000-0000-0000-0000-000000000001. On Supabase with RLS, insert these as that user or as the service role.
insert into public.confirmed_finds (id, user_id, object_name, place, confidence, found_at) values
('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'keys', 'kitchen table', 0.9, now() - interval '2 hours'),
('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'keys', 'front door hook', 0.7, now() - interval '2 days'),
('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'water bottle', 'lab bench by the window', 0.8, now() - interval '30 minutes')
on conflict (id) do nothing;

-- Room memory at the Harvard Yard demo tag (the printed FEEL tag feel-tag-01, 20 cm wide), shared by the demo user.
-- Positions are in the tag's frame: x right along the tag, y out into the room, z down; metres. Chalk answers
-- "Remembered here: exit about 6 meters ahead-right, seen 4 times, last 2 hours ago; water fountain about 3 meters
-- ahead-left, seen twice, last yesterday." (directions for someone standing at the tag with their back to it).
insert into public.anchors (id, user_id, venue_id, tag_id, label, x, y, z, confidence, shared, seen_at) values
('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -3.9, 5.2, 0.0, 0.9, true, now() - interval '4 hours'),
('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -4.1, 4.8, 0.1, 0.8, true, now() - interval '3 hours'),
('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -4.3, 5.0, -0.1, 0.7, true, now() - interval '1 day'),
('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'exit', -3.7, 5.6, 0.2, 0.95, true, now() - interval '2 hours'),
('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'water fountain', 2.0, 2.5, 0.3, 0.9, true, now() - interval '1 day'),
('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 'water fountain', 2.2, 2.3, 0.3, 0.6, true, now() - interval '1 day')
on conflict (id) do nothing;

-- The room's structure at the same tag, shared by the demo user: three visits (the visit maps of protocol/room-map-v1.json;
-- 10 cm cells in the tag's levelled frame, run-length encoded). Chalk merges them per cell into one 8 x 6 map, "28f2b10f2u6b":
-- the far wall stays, the chair seen on one visit of three goes. `python -m feel_chalk.context room-structure --venue harvard-yard
-- --tag feel-tag-01 --output structure.json` prints "Room structure at harvard-yard:feel-tag-01: 8 x 6 cells of 0.1 m,
-- 46 remembered (38 free, 8 blocked), merged from 3 visits."
insert into public.room_maps (id, user_id, venue_id, tag_id, cell_size, origin_x, origin_y, width, height, cells, shared, seen_at) values
('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, 0.0, 0.0, 6, 6, '14f2b4f2b8f6b', true, now() - interval '3 days'),
('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, -0.2, 0.0, 8, 6, '40f2u6b', true, now() - interval '1 day'),
('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'harvard-yard', 'feel-tag-01', 0.1, 0.1, 0.1, 4, 5, '9f1u1b5f4b', true, now() - interval '2 hours')
on conflict (id) do nothing;
