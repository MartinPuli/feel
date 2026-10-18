"""Feature classes. Keys are strings the phone can build without a lookup:
ObjectHistory.id is "<user_id>:<object name>", Venue.id is the venue slug the pack carries,
RoomMemory.id is "<venue_id>:<tag_id>", the printed FEEL tag the phone has just recognized, and
Path.id is "<venue_id>:<tag_id>:<from_x>,<from_y>:<label>", the pose in that tag's frame and the remembered target."""
from __future__ import annotations
from datetime import datetime

from chalk.features import DataFrame, FeatureTime, Primary, features, has_many, has_one


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
class Journey:
    """One walk from a printed tag toward a remembered target, in the tag's levelled frame: the steps the phone recorded,
    the blocked cell centres it saw, how long each cue took, and whether it arrived (feel_chalk/journeys.py). steps,
    obstacles and cue_latency_ms are the JSON arrays of the journeys table read as text. Written by the phone to the
    journeys table (chalk/sql/schema.sql); only rows their owner chose to share are read."""
    id: Primary[str]
    user_id: str
    venue_id: str
    tag_id: str
    session_id: str
    target_label: str
    started_at: FeatureTime
    arrived_at: datetime | None
    arrival_distance_m: float
    steps: str
    obstacles: str
    cue_latency_ms: str
    shared: bool
    # "<venue_id>:<tag_id>": the RoomMemory this journey belongs to.
    room_id: str


@features
class RoomMemory:
    """What FEEL remembers at one printed tag, across the users who shared their sightings, visits and journeys there."""
    id: Primary[str]
    venue_id: str
    tag_id: str
    anchors: DataFrame[Anchor] = has_many(lambda: Anchor.room_id == RoomMemory.id)
    maps: DataFrame[RoomMap] = has_many(lambda: RoomMap.room_id == RoomMemory.id)
    journeys: DataFrame[Journey] = has_many(lambda: Journey.room_id == RoomMemory.id)
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
    # The world map the path planner reads: the merged structure plus the shared journeys of the last 60 days (a cell a
    # step stood in is free, a cell an obstacle was seen in is blocked), as the same JSON as structure; None while nothing
    # is remembered. Recomputed daily by the scheduled query world_map (queries.py). Never a claim about the room now.
    world_map: str | None
    world_map_journeys: int


@features
class Path:
    """A suggested direction from a pose in a printed tag's frame to a target remembered there: A* over the room's world
    map (feel_chalk/path.py). Keyed "<venue_id>:<tag_id>:<from_x>,<from_y>:<label>" so the phone asks with one string.
    Never a claim that the way is clear: the live camera decides each step."""
    id: Primary[str]
    venue_id: str
    tag_id: str
    from_x: float
    from_y: float
    label: str
    # "<venue_id>:<tag_id>": the RoomMemory whose world map and remembered targets the path is planned over.
    room_id: str
    room: RoomMemory = has_one(lambda: Path.room_id == RoomMemory.id)
    # JSON list of [x, y] metres in the tag frame: the pose, each turn, the target. "[]" without a path.
    polyline: str
    # JSON list of [x, y] every 6 m along the polyline, the target last; what the phone's pins point at. "[]" without a path.
    progress_points: str
    length_m: float
    # "ok", "no target" (nothing remembered under that label), "no path" (the planner found none) or "no map".
    status: str
