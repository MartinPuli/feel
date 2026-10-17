# Chalk context: first live deployment (2026-10-17, 18:03 local)

Deployed from the committed `chalk/` project to environment `flnyc749e8d9` (project "Default");
see `apply-20261017.log`. Data source `feel_finds` is the Supabase session pooler with the read-only
`feel_chalk` role (`chalk/sql/access.sql`). Verified with `python -m feel_chalk.context` from this Mac:

```
$ python -m feel_chalk.context last-seen --user 00000000-0000-0000-0000-000000000001 --object keys
Keys: last confirmed at the kitchen table, 2 hours ago (2 finds on record).
$ python -m feel_chalk.context last-seen --user 00000000-0000-0000-0000-000000000001 --object "water bottle"
Water bottle: last confirmed at the lab bench by the window, 57 minutes ago.
$ python -m feel_chalk.context last-seen --user 00000000-0000-0000-0000-000000000001 --object laptop
No confirmed find of laptop is on record.
$ python -m feel_chalk.context venue-pack --venue harvard-yard --output harvard-yard-pack-from-chalk.json
Wrote harvard-yard-pack-from-chalk.json: sha256 37c629625c2e83ac7b06232aa26555915c1208b983ea7f23edae63477a1dda47.
```

The pack has the four seeded Harvard Yard entries and expires seven days after the query. The same
queries through the Chalk CLI (`chalk query --in object_history.id=... --out object_history.spoken`)
return the same values.

Two things the first deployment taught, now fixed in the code: online queries go to the
environment's engine host named in the token grant (`engines[env]`) at `/v1/query/online` with
`X-Chalk-Deployment-Type: engine`, not to api.chalk.ai; and a has-many resolver must declare the
child DataFrame columns it maps (`DataFrame[Find.id, ...]`), not the parent's relationship feature.
