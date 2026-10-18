"""Feature classes. Keys are strings the phone can build without a lookup:
ObjectHistory.id is "<user_id>:<object name>", Venue.id is the venue slug the pack carries, and
RoomMemory.id is "<venue_id>:<tag_id>", the printed FEEL tag the phone has just recognized."""
from __future__ import annotations
from datetime import datetime

from chalk.features import DataFrame, FeatureTime, Primary, features, has_many


@features
class Find:
    """One confirmed find: the user said "found it" after Where-is or a finder pointed at something.
    Rows are written by the phone to the confirmed_finds table (chalk/sql/schema.sql)."""
    id: Primary[str]
    user_id: str
    object_name: str
    place: str
    confidence: float
    found_at: FeatureTime
    # "<user_id>:<object_name>": the ObjectHistory this find belongs to.
    history_id: str


@features
class ObjectHistory:
    """What FEEL knows about one object for one user."""
    id: Primary[str]
    user_id: str
    object_name: str
    finds: DataFrame[Find] = has_many(lambda: Find.history_id == ObjectHistory.id)
    last_place: str | None
    last_seen_at: datetime | None
    finds_count: int
    # The sentence the assistant reads out; it never claims the object is still there.
    spoken: str


@features
class VenueEntry:
    """One reviewed statement about a venue, from an official HTTPS source."""
    id: Primary[str]
    venue_id: str
    kind: str
    name: str
    aliases: list[str]
    text: str
    source_url: str
    retrieved_at: datetime
    effective_from: datetime | None
    effective_until: datetime | None
    applies_to: str | None


@features
class Venue:
    id: Primary[str]
    name: str
    entries: DataFrame[VenueEntry] = has_many(lambda: VenueEntry.venue_id == Venue.id)
    # The downloadable pack (schema, sha256, payload) exactly as the phone validates it.
    pack: str
    pack_sha256: str


@features
class Anchor:
    """One remembered sighting of a target, in the frame of the printed room tag that was in view when the
    user confirmed it: x right along the tag, y out of the tag into the room, z down, in metres. Written by
    the phone to the anchors table (chalk/sql/schema.sql); only rows their owner chose to share are read."""
    id: Primary[str]
    user_id: str
    venue_id: str
    tag_id: str
    label: str
    x: float
    y: float
    z: float
    confidence: float
    shared: bool
    seen_at: FeatureTime
    # "<venue_id>:<tag_id>": the RoomMemory this sighting belongs to.
    room_id: str


@features
class RoomMap:
    """One visit's structural map of the room behind a printed tag: the floor grid the phone's route planner learned,
    as cells (unknown, free or blocked) in the tag's levelled frame, run-length encoded (feel_chalk/room_map.py).
    Written by the phone to the room_maps table (chalk/sql/schema.sql); only rows their owner chose to share are read."""
    id: Primary[str]
    user_id: str
    venue_id: str
    tag_id: str
    cell_size: float
    origin_x: float
    origin_y: float
    width: int
    height: int
    cells: str
    shared: bool
    seen_at: FeatureTime
    # "<venue_id>:<tag_id>": the RoomMemory this visit belongs to.
    room_id: str


@features
class RoomMemory:
    """What FEEL remembers at one printed tag, across the users who shared their sightings and visits there."""
    id: Primary[str]
    venue_id: str
    tag_id: str
    anchors: DataFrame[Anchor] = has_many(lambda: Anchor.room_id == RoomMemory.id)
    maps: DataFrame[RoomMap] = has_many(lambda: RoomMap.room_id == RoomMemory.id)
    # JSON list of remembered targets (label, x, y, z, sightings, last_seen_at), one per label, the position
    # being the median of that label's last 20 sightings; the phone reads it with FeelCore RememberedTarget.
    targets: str
    targets_count: int
    last_seen_at: datetime | None
    # The sentence the assistant reads out; past sightings only, never a claim about what is there now.
    spoken: str
    # The room's structure merged across the newest 50 shared visits (per cell: blocked when at least half of the visits
    # that saw it did, free otherwise), as the JSON the phone reads with FeelCore RoomMap to seed its route planner
    # before the camera has seen the room; None while nobody has shared a visit. Never a source for the pins.
    structure: str | None
    structure_visits: int
