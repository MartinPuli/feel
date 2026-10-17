"""Resolvers: rows from Postgres, the latest confirmed find per object, the spoken sentence, the venue
pack, and the room memory behind a printed tag. The sentences, the pack and the remembered positions
come from feel_chalk (history.py, venue_pack.py, anchors.py), so they are unit-tested without Chalk and
identical to what the local tools and the phone compute."""
from __future__ import annotations
from datetime import datetime, timezone
import json

from chalk import Now, online
from chalk.features import DataFrame, Features

from feel_chalk import anchors, history, venue_pack
from .features import Anchor, Find, ObjectHistory, RoomMemory, Venue, VenueEntry
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

ANCHOR_FIELDS = {"id": Anchor.id, "user_id": Anchor.user_id, "venue_id": Anchor.venue_id, "tag_id": Anchor.tag_id,
                 "label": Anchor.label, "x": Anchor.x, "y": Anchor.y, "z": Anchor.z, "confidence": Anchor.confidence,
                 "shared": Anchor.shared, "seen_at": Anchor.seen_at, "room_id": Anchor.room_id}
# Only sightings their owner chose to share leave that user's phone for the room's memory.
ANCHOR_SQL = ("select id::text as id, user_id::text as user_id, venue_id, tag_id, label, x, y, z, confidence, shared, seen_at, "
              "venue_id || ':' || tag_id as room_id from anchors where shared and venue_id || ':' || tag_id = :room_id "
              "order by seen_at desc limit 500")


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


def split_room_id(room_id: str) -> tuple[str, str]:
    venue_id, _, tag_id = room_id.partition(":")
    return venue_id, tag_id


def _aware(moment):
    if isinstance(moment, datetime) and moment.tzinfo is None:
        return moment.replace(tzinfo=timezone.utc)
    return moment


def room_targets(anchor_rows: list[dict]) -> tuple[str, int, datetime | None]:
    """The remembered targets as the JSON the phone reads, how many labels there are, and the newest sighting.
    Naive database times are read as UTC; rows anchors.remember cannot use are ignored, never guessed."""
    remembered = anchors.remember([dict(row, seen_at=_aware(row.get("seen_at"))) for row in anchor_rows])
    newest = max((t.last_seen_at for t in remembered), default=None)
    return anchors.to_json(remembered), len(remembered), newest


@online
def room_key(id: RoomMemory.id) -> Features[RoomMemory.venue_id, RoomMemory.tag_id]:
    venue_id, tag_id = split_room_id(id)
    return RoomMemory(venue_id=venue_id, tag_id=tag_id)


@online
def anchors_of_room(id: RoomMemory.id) -> RoomMemory.anchors:
    return feel_finds.query_string(ANCHOR_SQL, fields=ANCHOR_FIELDS, args={"room_id": id}).all()


@online
def remembered_targets(sightings: RoomMemory.anchors[Anchor.label, Anchor.x, Anchor.y, Anchor.z, Anchor.confidence, Anchor.seen_at]) -> Features[
        RoomMemory.targets, RoomMemory.targets_count, RoomMemory.last_seen_at]:
    targets, count, last_seen_at = room_targets(rows(sightings))
    return RoomMemory(targets=targets, targets_count=count, last_seen_at=last_seen_at)


@online
def spoken_room(targets: RoomMemory.targets, now: Now) -> RoomMemory.spoken:
    return anchors.spoken(anchors.from_json(targets), now)
