"""Resolvers: rows from Postgres, the latest confirmed find per object, the spoken sentence, and the
venue pack. The sentence and the pack come from feel_chalk (history.py, venue_pack.py), so they are
unit-tested without Chalk and byte-identical to what the local builder produces."""
from __future__ import annotations
from datetime import datetime, timezone
import json

from chalk import Now, online
from chalk.features import DataFrame, Features

from feel_chalk import history, venue_pack
from .features import Find, ObjectHistory, Venue, VenueEntry
from .sources import feel_finds

PACK_DAYS = 7

FIND_FIELDS = {"id": Find.id, "user_id": Find.user_id, "object_name": Find.object_name, "place": Find.place,
               "confidence": Find.confidence, "found_at": Find.found_at, "history_id": Find.history_id}
FIND_SQL = ("select id::text as id, user_id::text as user_id, object_name, place, confidence, found_at, "
            "user_id::text || ':' || object_name as history_id from confirmed_finds "
            "where user_id::text || ':' || object_name = :history_id order by found_at desc limit 200")

ENTRY_FIELDS = {"id": VenueEntry.id, "venue_id": VenueEntry.venue_id, "kind": VenueEntry.kind, "name": VenueEntry.name,
                "aliases": VenueEntry.aliases, "text": VenueEntry.text, "source_url": VenueEntry.source_url,
                "retrieved_at": VenueEntry.retrieved_at, "effective_from": VenueEntry.effective_from,
                "effective_until": VenueEntry.effective_until, "applies_to": VenueEntry.applies_to}
ENTRY_SQL = ("select id, venue_id, kind, name, aliases, text, source_url, retrieved_at, effective_from, effective_until, "
             "applies_to from venue_entries where venue_id = :venue_id order by id")


def rows(frame: DataFrame) -> list[dict]:
    """Rows as plain dicts keyed by the bare feature name ("find.place" -> "place")."""
    return [{key.split(".")[-1]: value for key, value in row.items()} for row in frame.to_pyarrow().to_pylist()]


@online
def history_key(id: ObjectHistory.id) -> Features[ObjectHistory.user_id, ObjectHistory.object_name]:
    user_id, _, object_name = id.partition(":")
    return ObjectHistory(user_id=user_id, object_name=object_name)


@online
def finds_of_history(id: ObjectHistory.id) -> ObjectHistory.finds:
    return feel_finds.query_string(FIND_SQL, fields=FIND_FIELDS, args={"history_id": id}).all()


@online
def last_find(finds: ObjectHistory.finds[Find.place, Find.found_at, Find.confidence]) -> Features[
        ObjectHistory.last_place, ObjectHistory.last_seen_at, ObjectHistory.finds_count]:
    summary = history.summarize(rows(finds))
    return ObjectHistory(last_place=summary.last_place, last_seen_at=summary.last_seen_at, finds_count=summary.count)


@online
def spoken_history(object_name: ObjectHistory.object_name, last_place: ObjectHistory.last_place,
                   last_seen_at: ObjectHistory.last_seen_at, finds_count: ObjectHistory.finds_count, now: Now) -> ObjectHistory.spoken:
    return history.spoken(object_name, history.Summary(last_place, last_seen_at, finds_count), now)


@online
def venue_row(id: Venue.id) -> Features[Venue.name]:
    return feel_finds.query_string("select id, name from venues where id = :id",
                                   fields={"id": Venue.id, "name": Venue.name}, args={"id": id}).one()


@online
def venue_entries(id: Venue.id) -> Venue.entries:
    return feel_finds.query_string(ENTRY_SQL, fields=ENTRY_FIELDS, args={"venue_id": id}).all()


def _stamp(moment) -> str | None:
    if not isinstance(moment, datetime):
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat()


def pack_source(venue_id: str, venue_name: str, entries: list[dict]) -> dict:
    """The builder's input, in the reviewed-source format (protocol/venue-pack-source.json)."""
    return {"venue_id": venue_id, "venue_name": venue_name, "entries": [
        {"id": row["id"], "kind": row["kind"], "name": row["name"], "aliases": list(row.get("aliases") or []),
         "text": row["text"], "source_url": row["source_url"], "retrieved_at": _stamp(row.get("retrieved_at")),
         "effective_from": _stamp(row.get("effective_from")), "effective_until": _stamp(row.get("effective_until")),
         "applies_to": row.get("applies_to")} for row in entries]}


@online
def build_pack(id: Venue.id, name: Venue.name, entries: Venue.entries, now: Now) -> Features[Venue.pack, Venue.pack_sha256]:
    pack = venue_pack.build(pack_source(id, name, rows(entries)), now, PACK_DAYS)
    return Venue(pack=json.dumps(pack, sort_keys=True, ensure_ascii=False), pack_sha256=pack["sha256"])
