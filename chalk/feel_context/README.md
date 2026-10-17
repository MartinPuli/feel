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
| `RoomMemory` | `<venue_id>:<tag_id>` | Per label, the median place of the last 20 sightings, the count, the newest time, and the spoken summary |

Named queries pin inputs and outputs: `last_seen` (`ObjectHistory.id` → `spoken`, `last_place`,
`last_seen_at`, `finds_count`), `venue_pack` (`Venue.id` → `pack`, `pack_sha256`) and `room_anchors`
(`RoomMemory.id` → `spoken`, `targets`, `targets_count`, `last_seen_at`).

The sentences, the pack and the remembered places are produced by `feel_chalk/history.py`,
`feel_chalk/venue_pack.py` and `feel_chalk/anchors.py`, the same code the local tools use, so
`tests/test_history.py`, `tests/test_anchors.py` and `tests/test_feel_context.py` cover them without a
deployment, a pack built by Chalk is byte-identical to one built locally, and the phone aggregates anchors
exactly as Chalk does (`protocol/room-memory-v1.json` is the vector both sides must reproduce).

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
```

The first prints "Keys: last confirmed at the kitchen table, 2 hours ago (2 finds on record)." from the
seed rows. The second writes a pack the phone accepts unchanged. The third prints "Remembered here: exit
about 6 meters ahead-right, seen 4 times, last 2 hours ago; water fountain about 3 meters ahead-left, seen
twice, last yesterday." and one line per remembered target.

First live deployment and the verified queries are recorded in
[docs/evidence/chalk-context](../../docs/evidence/chalk-context/QUERIES.md).

Not done yet, in order: the phone writing a find after "found it" and an anchor after a confirmed Where-is
target (Supabase REST, user JWT; `RoomMemory.shareAnchor` in the app is the empty function for the latter),
the `last_seen` and `room_anchors` assistant tools calling Chalk with a scoped token (the second would
fill the phone's local anchor store from the shared memory), and a scheduled query that rebuilds each
venue's pack daily (`ScheduledQuery` over `Venue.pack`; `queries.py` is where it goes).

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

## Privacy

Finds are personal data: a user id, an object word, a place and a time. Keep them under the
user's own account, never share across users without consent, and give retention a limit before
anything leaves the demo. No photo, audio or coordinate ever reaches this database.
