-- Demo rows for chalk/feel_context: the reviewed Harvard Yard entries (protocol/harvard-yard-source.json)
-- and three confirmed finds for one demo user. Run after schema.sql; safe to run twice.

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
