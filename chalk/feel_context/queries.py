"""Named queries the phone and feel_chalk.context call by name, so their inputs and outputs are
pinned in the deployment rather than chosen by each caller."""
from chalk import NamedQuery

from .features import ObjectHistory, RoomMemory, Venue

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
