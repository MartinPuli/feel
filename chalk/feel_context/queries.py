"""Named queries the phone and feel_chalk.context call by name, so their inputs and outputs are
pinned in the deployment rather than chosen by each caller."""
from chalk import NamedQuery

from .features import ObjectHistory, Venue

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
