"""Named queries the phone and feel_chalk.context call by name, so their inputs and outputs are
pinned in the deployment rather than chosen by each caller."""
from chalk import NamedQuery, ScheduledQuery

from .features import ObjectHistory, Path, RoomMemory, Venue

last_seen = NamedQuery(
    name="last_seen",
    input=[ObjectHistory.id],
    output=[ObjectHistory.spoken, ObjectHistory.last_place, ObjectHistory.last_seen_at, ObjectHistory.finds_count],
    description="Where one object was last confirmed for one user; id is '<user_id>:<object name>'.",
    owner="feel",
)

venue_pack = NamedQuery(
    name="venue_pack",
    input=[Venue.id],
    output=[Venue.pack, Venue.pack_sha256],
    description="The downloadable venue pack built from reviewed entries, valid seven days.",
    owner="feel",
)

room_anchors = NamedQuery(
    name="room_anchors",
    input=[RoomMemory.id],
    output=[RoomMemory.spoken, RoomMemory.targets, RoomMemory.targets_count, RoomMemory.last_seen_at],
    description="What is remembered at one printed FEEL tag, from shared sightings; id is '<venue_id>:<tag_id>'.",
    owner="feel",
)

room_structure = NamedQuery(
    name="room_structure",
    input=[RoomMemory.id],
    output=[RoomMemory.structure, RoomMemory.structure_visits],
    description="The structure of the room behind one printed FEEL tag, merged from shared visits: the floor-plan map the "
                "phone seeds its route planner with before the camera has seen the room; id is '<venue_id>:<tag_id>'.",
    owner="feel",
)

path = NamedQuery(
    name="path",
    input=[Path.id],
    output=[Path.polyline, Path.progress_points, Path.length_m, Path.status],
    description="A suggested direction over the room's world map from a pose in the tag frame to a target remembered there; "
                "id is '<venue_id>:<tag_id>:<from_x>,<from_y>:<label>'. Never a claim that the way is clear.",
    owner="feel",
)

progress_points = NamedQuery(
    name="progress_points",
    input=[Path.id],
    output=[Path.progress_points, Path.status],
    description="The points every 6 m along the suggested path, the target last: what the phone's pins point at next; "
                "id is '<venue_id>:<tag_id>:<from_x>,<from_y>:<label>'.",
    owner="feel",
)

# Recomputes each remembered room's world map (merged structure plus the shared journeys of the last 60 days) once a day,
# over the RoomMemory ids the cron resolver rooms_with_memory (resolvers.py) ingests, and keeps them in the online store.
world_map = ScheduledQuery(
    name="world_map",
    schedule="0 4 * * *",
    output=[RoomMemory.world_map, RoomMemory.world_map_journeys],
    recompute_features=True,
    store_online=True,
    store_offline=True,
)
