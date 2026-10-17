# FEEL context on Chalk

The features Chalk serves to FEEL's assistant, and the database they read. Deployed from `chalk/`
(`chalk.yaml` is there); queried by `python -m feel_chalk.context` and, later, by the phone.

| Feature class | Key | What it answers |
|---|---|---|
| `Find` | row id | One confirmed find: user, object, place, confidence, time (`found_at` is the feature time) |
| `ObjectHistory` | `<user_id>:<object name>` | Latest confirmed place and time, count, and the sentence the assistant reads out |
| `VenueEntry` | entry id | One reviewed statement from an official HTTPS source, with effective dates |
| `Venue` | venue slug | The downloadable venue pack built from its entries, with its SHA-256 |

Named queries pin inputs and outputs: `last_seen` (`ObjectHistory.id` → `spoken`, `last_place`,
`last_seen_at`, `finds_count`) and `venue_pack` (`Venue.id` → `pack`, `pack_sha256`).

The sentence and the pack are produced by `feel_chalk/history.py` and `feel_chalk/venue_pack.py`,
the same code the local tools use, so `tests/test_history.py` and `tests/test_feel_context.py`
cover them without a deployment, and a pack built by Chalk is byte-identical to one built locally.

## The database, and what the Supabase values are for

`chalk/.env` now has `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Those are the project's **API**
address and anon key: what the phone will use (with a signed-in user) to write confirmed finds
through Supabase's REST API under row-level security.

Chalk does not use either. Its PostgreSQL data source connects to the **database** behind that
project, so it needs host, port, database name, user and password. On Supabase they are under
Project Settings → Database → Connection string; use the **Session pooler** entry (IPv4, port 5432,
user `postgres.<project ref>`) and the database password, not the publishable key. Preferably make
Chalk its own read-only user first:

```sql
create role feel_chalk login password '<generate one>';
grant usage on schema public to feel_chalk;
grant select on public.confirmed_finds, public.venues, public.venue_entries to feel_chalk;
```

Then:

1. Run `chalk/sql/schema.sql` in the Supabase SQL editor, then `chalk/sql/seed.sql` for the demo rows.
2. In the Chalk dashboard, Data Sources → Add → PostgreSQL, **name `feel_finds`**, with the values above.
   Chalk's "test connection" must pass before a deployment can resolve anything.
3. Install the Chalk CLI (`curl -s -L https://api.chalk.ai/install.sh | sh`), `chalk login`,
   `chalk environment <CHALK_ENV_ID>`, then from `chalk/`: `chalk apply --branch feel-context` to try it,
   and `chalk apply` for the environment.
4. Verify from this Mac (service token in `chalk/.env`):

```sh
python -m feel_chalk.context last-seen --user 00000000-0000-0000-0000-000000000001 --object keys
python -m feel_chalk.context venue-pack --venue harvard-yard --output data/harvard-yard-from-chalk.json
```

The first prints "Keys: last confirmed at the kitchen table, 2 hours ago (2 finds on record)." from the
seed rows. The second writes a pack the phone accepts unchanged.

Not done yet, in order: the phone writing a find after "found it" (Supabase REST, user JWT), the
`last_seen` assistant tool calling Chalk with a scoped token, and a scheduled query that rebuilds
each venue's pack daily (`ScheduledQuery` over `Venue.pack`; `queries.py` is where it goes).

## Privacy

Finds are personal data: a user id, an object word, a place and a time. Keep them under the
user's own account, never share across users without consent, and give retention a limit before
anything leaves the demo. No photo, audio or coordinate ever reaches this database.
