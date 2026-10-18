# FEEL context on Chalk

The features Chalk serves to FEEL's assistant, and the database they read. Deployed from `chalk/`
(`chalk.yaml` is there); queried by `python -m feel_chalk.context` and, later, by the phone.

| Feature class | Key | What it answers |
|---|---|---|
| `Find` | row id | One confirmed find: user, object, place, confidence, time (`found_at` is the feature time) |
| `ObjectHistory` | `<user_id>:<object name>` | Latest confirmed place and time, count, and the sentence the assistant reads out |
| `VenueEntry` | entry id | One reviewed statement from an official HTTPS source, with effective dates |
| `Venue` | venue slug | The downloadable venue pack built from its entries, with its SHA-256 |
| `Anchor` | row id | One confirmed sighting of a target in a printed room tag's frame (x, y, z in metres), shared by its owner |
| `RoomMap` | row id | One visit's structural map of the room behind a tag: 10 cm cells (unknown, free, blocked) in the tag's levelled frame, run-length encoded, shared by its owner |
| `RoomMemory` | `<venue_id>:<tag_id>` | Per label, the median place of the last 20 sightings, the count, the newest time, and the spoken summary; and the room's structure merged from the newest 50 shared visits |

Named queries pin inputs and outputs: `last_seen` (`ObjectHistory.id` → `spoken`, `last_place`,
`last_seen_at`, `finds_count`), `venue_pack` (`Venue.id` → `pack`, `pack_sha256`), `room_anchors`
(`RoomMemory.id` → `spoken`, `targets`, `targets_count`, `last_seen_at`) and `room_structure`
(`RoomMemory.id` → `structure`, `structure_visits`).

The sentences, the pack, the remembered places and the merged map are produced by `feel_chalk/history.py`,
`feel_chalk/venue_pack.py`, `feel_chalk/anchors.py` and `feel_chalk/room_map.py`, the same code the local tools
use, so `tests/test_history.py`, `tests/test_anchors.py`, `tests/test_room_map.py` and `tests/test_feel_context.py`
cover them without a deployment, a pack built by Chalk is byte-identical to one built locally, and the phone
aggregates anchors and merges maps exactly as Chalk does (`protocol/room-memory-v1.json` and
`protocol/room-map-v1.json` are the vectors both sides must reproduce).

## The database, and what the Supabase values are for

`chalk/.env` now has `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Those are the project's **API**
address and anon key: what the phone will use (with a signed-in user) to write confirmed finds
through Supabase's REST API under row-level security.

Chalk does not use either. Its PostgreSQL data source connects to the **database** behind that
project, so it needs host, port, database name, user and password. On Supabase they are under the
**Connect** button → **Session pooler** (IPv4, port 5432, database `postgres`); the user is written
`<role>.<project ref>`. Give Chalk its own read-only role rather than `postgres`: `sql/access.sql`
creates `feel_chalk`, grants it select, and adds the row-level-security policies it needs (a plain role
is subject to RLS too, so without them Chalk would read zero finds).

Then:

1. Run `chalk/sql/schema.sql` in the Supabase SQL editor, then `chalk/sql/seed.sql` for the demo rows, then
   `chalk/sql/access.sql` with a generated password in place of the placeholder.
2. In the Chalk dashboard, Data Sources → Add → PostgreSQL, **name `feel_finds`**: the session pooler host and
   port 5432, database `postgres`, user `feel_chalk.<project ref>`, that password.
   Chalk's "test connection" must pass before a deployment can resolve anything.
3. Install the Chalk CLI (`curl -s -L https://api.chalk.ai/install.sh | sh`). With `CHALK_CLIENT_ID` and
   `CHALK_CLIENT_SECRET` exported from `chalk/.env` no browser login is needed. Then from `chalk/`:
   `chalk environment <CHALK_ENV_ID>` and `chalk apply --await --force`. `chalk.yaml` names the Chalk project
   ("Default", the one that owns the environment); `.chalkignore` keeps tests, evaluations and data out of the upload.
4. Verify from this Mac (service token in `chalk/.env`):

```sh
python -m feel_chalk.context last-seen --user 00000000-0000-0000-0000-000000000001 --object keys
python -m feel_chalk.context venue-pack --venue harvard-yard --output data/harvard-yard-from-chalk.json
python -m feel_chalk.context room-anchors --venue harvard-yard --tag feel-tag-01
python -m feel_chalk.context room-structure --venue harvard-yard --tag feel-tag-01 --output data/harvard-yard-structure.json
```

The first prints "Keys: last confirmed at the kitchen table, 2 hours ago (2 finds on record)." from the
seed rows. The second writes a pack the phone accepts unchanged. The third prints "Remembered here: exit
about 6 meters ahead-right, seen 4 times, last 2 hours ago; water fountain about 3 meters ahead-left, seen
twice, last yesterday." and one line per remembered target. The fourth prints "Room structure at
harvard-yard:feel-tag-01: 8 x 6 cells of 0.1 m, 46 remembered (38 free, 8 blocked), merged from 3 visits."
and writes the merged map the phone reads with FeelCore `RoomMap`. A database that ran the earlier files
before the `room_maps` table existed gets it from `sql/upgrade-room-maps.sql`.

First live deployment and the verified queries are recorded in
[docs/evidence/chalk-context](../../docs/evidence/chalk-context/QUERIES.md).

Not done yet, in order: the phone writing a find after "found it", an anchor after a confirmed Where-is
target and a visit's map when sensing stops (Supabase REST, user JWT; `RoomMemory.shareAnchor` and
`RoomMemory.shareStructure` in the app are the empty functions for the last two), the `last_seen`,
`room_anchors` and `room_structure` assistant tools calling Chalk with a scoped token (the second would
fill the phone's local anchor store from the shared memory, the third its visits: `RoomMemory.fetchSharedStructure`
is that empty function), and a scheduled query that rebuilds each venue's pack daily (`ScheduledQuery` over
`Venue.pack`; `queries.py` is where it goes).

## Room memory

![Room memory](../../docs/diagrams/room-memory.svg)

**The tag.** ARKit's world origin changes every session, so a position remembered yesterday means nothing
today on its own. FEEL fixes the room with a printed tag: `ios/Lantern/Resources/feel-tag-01.png`
(drawn by `ios/scripts/make_room_tag.py`), printed **20 cm wide** and hung flat at about chest height.
ARKit image detection recognizes it within about a second and gives its image anchor; the app tells ARKit
the 20 cm width, so a tag printed at another size would put every remembered place at the wrong distance.
The anchor is the room frame: x to the right along the tag, y out of the tag into the room, z down along
the tag, in metres. The phone stores every confirmed target ("found it", or arriving at a Where-is target)
in that frame, and on the next visit a "where is the exit?" with the tag seen points the pins at once
("Last time the exit was about 2 meters ahead to your left. Pins point there. Say photo to check again.")
instead of taking a photo. The photo path is one word away, and the pins never stop showing live depth.

**What Chalk aggregates.** `Anchor` rows whose owner set `shared = true` are read per
`<venue_id>:<tag_id>`; `RoomMemory` resolves them per label into the per-axis median of the last 20
sightings (one bad confirmation moves nothing much), the sighting count and the newest time, as a JSON
list the phone can read with FeelCore's `RememberedTarget`, plus a spoken summary. Directions in that
summary are for someone standing at the tag with their back to it ("ahead-right"); the phone's own cue is
relative to the user because it knows their pose. Everything is phrased as a past sighting; nothing says
where a thing is now.

**Privacy.** Anchors are personal data: a user id, a word, a position relative to a named tag in a named
venue, and a time; together they say where someone was and when. They stay on the phone by default. A row
reaches the shared memory only when the user opted in (`shared = true`, enforced by the row-level security
policies in `sql/schema.sql` and `sql/access.sql`), and Chalk reads nothing else. Keep retention limited and
deletion possible before anything leaves the demo. No photo, audio or GPS coordinate is ever part of an anchor.

## Room structure

![Room structure](../../docs/diagrams/room-structure.svg)

**What the phone keeps.** While sensing runs, FeelCore's `FloorGrid` classifies 10 cm floor cells from LiDAR as free
or blocked for the route arrows and forgets them when the session stops or tracking resets. With a printed tag in
view, the grid is first exported into the tag's levelled frame (`RoomMap`: cell size, origin, width, height and
run-length encoded cells) and stored per tag as one visit (`RoomMemoryStore`, the newest ten), provided the camera
classified at least 20 cells. On the next visit the first sighting of the tag in a world seeds the new session's grid
with the merge of the stored visits as a prior, so "where is the exit" with a remembered exit anchor gives a route
arrow before the camera has seen the room. The prior fills only cells the camera has not classified yet; every live
classification overrides it, a tracking reset drops it with the world, and the pins never read it.

**What Chalk merges.** `RoomMap` rows whose owner set `shared = true` are read per `<venue_id>:<tag_id>`;
`RoomMemory.structure` is the per-cell vote over the newest 50 visits: blocked when at least half of the visits that
observed the cell saw it blocked (a tie goes to blocked, since a missed wall costs more than a spurious one the live
camera overrides), free otherwise, unknown where no visit looked. Walls persist; a chair that moved is gone after two
more visits that see the floor there. `feel_chalk/room_map.py` is the same rule as FeelCore's `RoomMap.merge`,
`protocol/room-map-v1.json` is the vector both must reproduce, and `sql/seed.sql` carries its three visits, so
`room-structure --venue harvard-yard --tag feel-tag-01` prints the merged 8 × 6 map once deployed. The phone's upload
of a visit (`RoomMemory.shareStructure`) and its download of the merged map (`RoomMemory.fetchSharedStructure`) are
the two empty functions still to wire; the device test of the tag this all depends on is pending.

**Privacy.** A visit map says which cells of a named room someone walked through, so it is personal data like an
anchor: it stays on the phone unless the user opted in, and Chalk reads only shared rows (`sql/access.sql`). It holds
no photo, audio or GPS coordinate, and nothing in it is a claim about the room now: a remembered wall is only a reason
for the planner to prefer another way.

## Privacy

Finds are personal data: a user id, an object word, a place and a time. Keep them under the
user's own account, never share across users without consent, and give retention a limit before
anything leaves the demo. No photo, audio or coordinate ever reaches this database.
