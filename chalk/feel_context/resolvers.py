"""Resolvers: rows from Postgres, the latest confirmed find per object, the spoken sentence, the venue
pack, the room memory behind a printed tag (remembered targets, the room's merged structure, the world map
with the last 60 days of shared journeys) and a suggested path over that map. The sentences, the pack, the
remembered positions, the maps and the path come from feel_chalk (history.py, venue_pack.py, anchors.py,
room_map.py, journeys.py, path.py), so they are unit-tested without Chalk and identical to what the local
tools and the phone compute."""
from __future__ import annotations
from datetime import datetime, timezone
import json

from chalk import Now, offline, online
from chalk.features import DataFrame, Features

from feel_chalk import anchors, history, journeys, path, room_map, venue_pack
from .features import Anchor, Find, Journey, ObjectHistory, Path, RoomMap, RoomMemory, Venue, VenueEntry
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

MAP_FIELDS = {"id": RoomMap.id, "user_id": RoomMap.user_id, "venue_id": RoomMap.venue_id, "tag_id": RoomMap.tag_id,
              "cell_size": RoomMap.cell_size, "origin_x": RoomMap.origin_x, "origin_y": RoomMap.origin_y, "width": RoomMap.width,
              "height": RoomMap.height, "cells": RoomMap.cells, "shared": RoomMap.shared, "seen_at": RoomMap.seen_at, "room_id": RoomMap.room_id}
# Only visits their owner chose to share leave that user's phone for the room's structure; the newest room_map.KEEP vote.
MAP_SQL = ("select id::text as id, user_id::text as user_id, venue_id, tag_id, cell_size, origin_x, origin_y, width, height, cells, shared, "
           "seen_at, venue_id || ':' || tag_id as room_id from room_maps where shared and venue_id || ':' || tag_id = :room_id "
           f"order by seen_at desc limit {room_map.KEEP}")

JOURNEY_FIELDS = {"id": Journey.id, "user_id": Journey.user_id, "venue_id": Journey.venue_id, "tag_id": Journey.tag_id,
                  "session_id": Journey.session_id, "target_label": Journey.target_label, "started_at": Journey.started_at,
                  "arrived_at": Journey.arrived_at, "arrival_distance_m": Journey.arrival_distance_m, "steps": Journey.steps,
                  "obstacles": Journey.obstacles, "cue_latency_ms": Journey.cue_latency_ms, "shared": Journey.shared, "room_id": Journey.room_id}
# Only journeys their owner chose to share leave that user's phone for the room's world map; the JSON columns are read as
# text and parsed by feel_chalk.journeys. The 60-day window is applied in Python against the query's own clock.
JOURNEY_SQL = ("select id::text as id, user_id::text as user_id, venue_id, tag_id, session_id, target_label, started_at, arrived_at, "
               "arrival_distance_m, steps::text as steps, obstacles::text as obstacles, cue_latency_ms::text as cue_latency_ms, shared, "
               "venue_id || ':' || tag_id as room_id from journeys where shared and venue_id || ':' || tag_id = :room_id "
               "order by started_at desc limit 200")
# Every room anyone shared a visit or a journey at: the rows the scheduled query world_map recomputes daily.
ROOMS_SQL = ("select distinct venue_id || ':' || tag_id as id, venue_id, tag_id from room_maps where shared "
             "union select distinct venue_id || ':' || tag_id as id, venue_id, tag_id from journeys where shared")


def rows(frame: DataFrame) -> list[dict]:
    """Rows as plain dicts keyed by the bare feature name ("find.place" -> "place")."""
    return [{key.split(".")[-1]: value for key, value in row.items()} for row in frame.to_pyarrow().to_pylist()]


@online
def history_key(id: ObjectHistory.id) -> Features[ObjectHistory.user_id, ObjectHistory.object_name]:
    user_id, _, object_name = id.partition(":")
    return ObjectHistory(user_id=user_id, object_name=object_name)


@online
def finds_of_history(id: ObjectHistory.id) -> DataFrame[Find.id, Find.user_id, Find.object_name, Find.place, Find.confidence,
                                                        Find.found_at, Find.history_id]:
    """The finds behind ObjectHistory.finds: Chalk matches this DataFrame to the has_many join on history_id."""
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
    return feel_finds.query_string("select name from venues where id = :id", fields={"name": Venue.name}, args={"id": id}).one()


@online
def venue_entries(id: Venue.id) -> DataFrame[VenueEntry.id, VenueEntry.venue_id, VenueEntry.kind, VenueEntry.name, VenueEntry.aliases,
                                             VenueEntry.text, VenueEntry.source_url, VenueEntry.retrieved_at, VenueEntry.effective_from,
                                             VenueEntry.effective_until, VenueEntry.applies_to]:
    """The entries behind Venue.entries, matched to the has_many join on venue_id."""
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
def anchors_of_room(id: RoomMemory.id) -> DataFrame[Anchor.id, Anchor.user_id, Anchor.venue_id, Anchor.tag_id, Anchor.label, Anchor.x, Anchor.y,
                                                     Anchor.z, Anchor.confidence, Anchor.shared, Anchor.seen_at, Anchor.room_id]:
    """The sightings behind RoomMemory.anchors, matched to the has_many join on room_id (shared rows only)."""
    return feel_finds.query_string(ANCHOR_SQL, fields=ANCHOR_FIELDS, args={"room_id": id}).all()


@online
def remembered_targets(sightings: RoomMemory.anchors[Anchor.label, Anchor.x, Anchor.y, Anchor.z, Anchor.confidence, Anchor.seen_at]) -> Features[
        RoomMemory.targets, RoomMemory.targets_count, RoomMemory.last_seen_at]:
    targets, count, last_seen_at = room_targets(rows(sightings))
    return RoomMemory(targets=targets, targets_count=count, last_seen_at=last_seen_at)


@online
def spoken_room(targets: RoomMemory.targets, now: Now) -> RoomMemory.spoken:
    return anchors.spoken(anchors.from_json(targets), now)


def _newest_first(rows: list[dict]) -> list[dict]:
    """Rows by seen_at, newest first; naive database times are read as UTC and rows without a time count as oldest."""
    oldest = datetime.min.replace(tzinfo=timezone.utc)
    return sorted(rows, key=lambda row: _aware(row.get('seen_at')) if isinstance(row.get('seen_at'), datetime) else oldest, reverse=True)


def room_structure(map_rows: list[dict]) -> tuple[str | None, int]:
    """The room's structure merged from its newest room_map.KEEP shared visits, as the JSON the phone reads with FeelCore
    RoomMap, and how many visits voted. Rows room_map.validate cannot use are ignored, never guessed; (None, 0) without any."""
    visits = room_map.usable(_newest_first(map_rows))[:room_map.KEEP]
    merged = room_map.merge(visits)
    return (merged.to_json() if merged else None, len(visits))


@online
def maps_of_room(id: RoomMemory.id) -> DataFrame[RoomMap.id, RoomMap.user_id, RoomMap.venue_id, RoomMap.tag_id, RoomMap.cell_size, RoomMap.origin_x,
                                                 RoomMap.origin_y, RoomMap.width, RoomMap.height, RoomMap.cells, RoomMap.shared, RoomMap.seen_at,
                                                 RoomMap.room_id]:
    """The visits behind RoomMemory.maps, matched to the has_many join on room_id (shared rows only)."""
    return feel_finds.query_string(MAP_SQL, fields=MAP_FIELDS, args={"room_id": id}).all()


@online
def merged_structure(visits: RoomMemory.maps[RoomMap.cell_size, RoomMap.origin_x, RoomMap.origin_y, RoomMap.width, RoomMap.height, RoomMap.cells,
                                             RoomMap.seen_at]) -> Features[RoomMemory.structure, RoomMemory.structure_visits]:
    structure, count = room_structure(rows(visits))
    return RoomMemory(structure=structure, structure_visits=count)


@online
def journeys_of_room(id: RoomMemory.id) -> DataFrame[Journey.id, Journey.user_id, Journey.venue_id, Journey.tag_id, Journey.session_id,
                                                     Journey.target_label, Journey.started_at, Journey.arrived_at, Journey.arrival_distance_m,
                                                     Journey.steps, Journey.obstacles, Journey.cue_latency_ms, Journey.shared, Journey.room_id]:
    """The walks behind RoomMemory.journeys, matched to the has_many join on room_id (shared rows only)."""
    return feel_finds.query_string(JOURNEY_SQL, fields=JOURNEY_FIELDS, args={"room_id": id}).all()


def room_world_map(structure: str | None, journey_rows: list[dict], now: datetime) -> tuple[str | None, int]:
    """The world map as the JSON the planner and the phone read, and how many journeys of the last 60 days are in it.
    Rows journeys.from_row cannot use are ignored, never guessed; (None, 0) without anything remembered."""
    merged = room_map.from_json(structure) if isinstance(structure, str) else None
    recent = journeys.within_days(journeys.usable(journey_rows), _aware(now))
    world = journeys.world_map(merged, recent, _aware(now))
    return (world.to_json() if world else None, len(recent))


@online
def world_map_of_room(structure: RoomMemory.structure,
                      walks: RoomMemory.journeys[Journey.user_id, Journey.venue_id, Journey.tag_id, Journey.session_id, Journey.target_label,
                                                 Journey.started_at, Journey.arrived_at, Journey.arrival_distance_m, Journey.steps,
                                                 Journey.obstacles, Journey.cue_latency_ms],
                      now: Now) -> Features[RoomMemory.world_map, RoomMemory.world_map_journeys]:
    world, count = room_world_map(structure, rows(walks), now)
    return RoomMemory(world_map=world, world_map_journeys=count)


@offline(cron="0 3 * * *")
def rooms_with_memory() -> DataFrame[RoomMemory.id, RoomMemory.venue_id, RoomMemory.tag_id]:
    """Every room with a shared visit or journey, ingested daily so the scheduled query world_map (queries.py) has
    the RoomMemory ids to recompute."""
    return feel_finds.query_string(ROOMS_SQL, fields={"id": RoomMemory.id, "venue_id": RoomMemory.venue_id, "tag_id": RoomMemory.tag_id}).all()


def split_path_id(path_id: str) -> tuple[str, str, float, float, str]:
    """Path.id "<venue_id>:<tag_id>:<from_x>,<from_y>:<label>" into its parts; raises ValueError for anything else."""
    parts = path_id.split(":")
    if len(parts) != 4:
        raise ValueError(f"path id must be '<venue_id>:<tag_id>:<from_x>,<from_y>:<label>', not {path_id!r}")
    venue_id, tag_id, pose, label = parts
    x_text, _, y_text = pose.partition(",")
    try:
        from_x, from_y = float(x_text), float(y_text)
    except ValueError:
        raise ValueError(f"path id pose must be '<from_x>,<from_y>' in metres, not {pose!r}") from None
    if not (abs(from_x) <= room_map.REACH and abs(from_y) <= room_map.REACH):
        raise ValueError(f"path id pose {pose!r} is farther than {room_map.REACH:g} m from the tag")
    label = anchors.normalize_label(label)
    if not venue_id or not tag_id or not label:
        raise ValueError(f"path id needs a venue, a tag and a label: {path_id!r}")
    return venue_id, tag_id, from_x, from_y, label


@online
def path_key(id: Path.id) -> Features[Path.venue_id, Path.tag_id, Path.from_x, Path.from_y, Path.label, Path.room_id]:
    venue_id, tag_id, from_x, from_y, label = split_path_id(id)
    return Path(venue_id=venue_id, tag_id=tag_id, from_x=from_x, from_y=from_y, label=label, room_id=f"{venue_id}:{tag_id}")


def suggested_path(from_x: float, from_y: float, label: str, world: str | None, targets: str | None) -> dict:
    """The polyline and progress points (JSON) from a pose to the target remembered under `label`, with the length and
    a status: "ok", "no target", "no map" or "no path". Pure, so the resolver and the tests share it."""
    remembered = {t.label: t for t in anchors.from_json(targets)} if isinstance(targets, str) else {}
    none = {"polyline": "[]", "progress_points": "[]", "length_m": 0.0}
    if label not in remembered:
        return dict(none, status="no target")
    world_map = room_map.from_json(world) if isinstance(world, str) else None
    if world_map is None:
        return dict(none, status="no map")
    target = remembered[label]
    polyline = path.plan(world_map, (from_x, from_y), (target.x, target.y))
    if polyline is None:
        return dict(none, status="no path")
    return {"polyline": json.dumps([list(p) for p in polyline]), "progress_points": json.dumps([list(p) for p in path.progress_points(polyline)]),
            "length_m": round(path.length(polyline), 3), "status": "ok"}


@online
def plan_path(from_x: Path.from_x, from_y: Path.from_y, label: Path.label, world: Path.room.world_map, targets: Path.room.targets) -> Features[
        Path.polyline, Path.progress_points, Path.length_m, Path.status]:
    return Path(**suggested_path(from_x, from_y, label, world, targets))
