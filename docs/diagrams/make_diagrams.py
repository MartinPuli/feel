"""Draws the FEEL diagrams as plain SVG (python3 docs/diagrams/make_diagrams.py). Hand-placed on a
grid so they stay legible in a README; edit the figure functions, rerun, commit the SVGs."""
from __future__ import annotations
from pathlib import Path

# Chalkboard theme, matching docs/diagrams/chalk-journey-loop.webp: a dark green board, chalk-white text,
# dark cards. Phone and body cards have a pale edge and blue arrows; Chalk cards have a yellow edge with a
# hatched shadow and yellow arrows; other services are grey.
INK, MUTED, PAPER = '#e9ece7', '#a9b8b0', '#24352f'
PHONE, PHONE_EDGE = '#15231e', '#9db3aa'          # on the phone / on the body
CHALK, CHALK_EDGE = '#15231e', '#e3c558'          # through Chalk
CLOUD, CLOUD_EDGE = '#1a2b26', '#8e9aa6'          # other services
ACCENT = '#f0a25a'                                # FEEL's pin orange, chalk-tinted: the thing the figure is about
FLOW = '#8fbfe8'                                  # blue arrows: what the phone and body do on their own
FONT = "'Avenir Next', 'Helvetica Neue', Helvetica, Arial, sans-serif"
HERE = Path(__file__).resolve().parent


class Figure:
    def __init__(self, width: int, height: int, title: str, label: str):
        self.w, self.h, self.title, self.label = width, height, title, label
        self.parts: list[str] = []

    def esc(self, text: str) -> str:
        return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    def box(self, x, y, w, h, title, lines=(), fill=PHONE, edge=PHONE_EDGE, dashed=False, accent=False, small=False):
        dash = ' stroke-dasharray="6 4"' if dashed else ''
        stroke = ACCENT if accent else edge
        if edge == CHALK_EDGE:  # Chalk cards carry a hatched shadow, as in the hand-drawn journey figure.
            self.parts.append(f'<rect x="{x + 5}" y="{y + 5}" width="{w}" height="{h}" rx="9" fill="url(#hatch)"/>')
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="{fill}" stroke="{stroke}" stroke-width="{2.2 if accent else 1.6}"{dash}/>')
        size = 12 if small else 13.5
        ty = y + (17 if small else 20)
        self.parts.append(f'<text x="{x + w / 2}" y="{ty}" text-anchor="middle" font-size="{size}" font-weight="700" fill="{INK}">{self.esc(title)}</text>')
        for i, line in enumerate(lines):
            self.parts.append(f'<text x="{x + w / 2}" y="{ty + 16 + i * 14}" text-anchor="middle" font-size="11" fill="{MUTED}">{self.esc(line)}</text>')

    def group(self, x, y, w, h, label, edge=MUTED):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="none" stroke="{edge}" stroke-width="1" stroke-dasharray="3 5" opacity="0.7"/>')
        self.parts.append(f'<text x="{x + 10}" y="{y - 7}" font-size="11.5" font-weight="700" fill="{edge}" letter-spacing="1">{self.esc(label.upper())}</text>')

    def arrow(self, x1, y1, x2, y2, label='', color=FLOW, dashed=False, via=None, label_dx=0, label_dy=-6):
        if color in (INK, PHONE_EDGE): color = FLOW  # phone and body flows are blue, as in the journey figure
        marker = {FLOW: 'flow', CHALK_EDGE: 'chalk', ACCENT: 'accent', MUTED: 'muted', PHONE_EDGE: 'phone'}[color]
        dash = ' stroke-dasharray="5 4"' if dashed else ''
        points = [(x1, y1)] + (via or []) + [(x2, y2)]
        path = 'M ' + ' L '.join(f'{px} {py}' for px, py in points)
        self.parts.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"{dash} marker-end="url(#{marker})"/>')
        if label:
            mid = points[len(points) // 2] if len(points) > 2 else ((x1 + x2) / 2, (y1 + y2) / 2)
            lx, ly = mid[0] + label_dx, mid[1] + label_dy
            lines = label.split('\n')
            width = max(len(line) for line in lines) * 6.1 + 8
            height = 13 * len(lines) + 4
            self.parts.append(f'<rect x="{lx - width / 2}" y="{ly - 11}" width="{width}" height="{height}" rx="3" fill="{PAPER}" opacity="0.92"/>')
            for i, line in enumerate(lines):
                self.parts.append(f'<text x="{lx}" y="{ly + i * 13}" text-anchor="middle" font-size="10.5" fill="{color}">{self.esc(line)}</text>')

    def note(self, x, y, text, color=MUTED, anchor='start', size=11):
        self.parts.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" font-style="italic" fill="{color}">{self.esc(text)}</text>')

    def save(self, name: str) -> Path:
        markers = ''.join(
            f'<marker id="{mid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">'
            f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{color}"/></marker>'
            for mid, color in (('flow', FLOW), ('chalk', CHALK_EDGE), ('accent', ACCENT), ('muted', MUTED), ('phone', PHONE_EDGE)))
        hatch = (f'<pattern id="hatch" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
                 f'<line x1="0" y1="0" x2="0" y2="7" stroke="{CHALK_EDGE}" stroke-width="1.2" opacity="0.45"/></pattern>'
                 f'<radialGradient id="board" cx="50%" cy="40%" r="75%"><stop offset="0" stop-color="#2b4039"/><stop offset="1" stop-color="{PAPER}"/></radialGradient>')
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}" '
               f'role="img" aria-label="{self.esc(self.label)}" font-family="{FONT}">'
               f'<title>{self.esc(self.title)}</title><defs>{markers}{hatch}</defs>'
               f'<rect x="0" y="0" width="{self.w}" height="{self.h}" rx="18" fill="url(#board)"/>'
               f'<text x="20" y="30" font-size="16" font-weight="700" fill="{INK}">{self.esc(self.title)}</text>'
               + ''.join(self.parts) + '</svg>\n')
        path = HERE / name
        path.write_text(svg, encoding='utf-8')
        return path


def system() -> Figure:
    f = Figure(1140, 600, 'FEEL at a glance: what runs on the body, on the phone, and through Chalk',
               'FEEL system: the LiDAR phone drives the tactile puck directly; the assistant reaches OpenAI for voice and Chalk for the vision gateway, context features and evaluations.')
    f.group(20, 70, 250, 500, 'On the body')
    f.box(40, 288, 210, 86, 'iPhone, chest-mounted', ('LiDAR depth 60 Hz · camera', 'microphone · ARKit pose'))
    f.box(40, 452, 210, 86, 'FEEL puck', ('ESP32 · BLE · six servos', '6 columns × 4 rows of pins'))
    f.arrow(250, 331, 320, 331, color=PHONE_EDGE, label='depth + pose', label_dy=-8)
    f.arrow(320, 352, 250, 495, color=PHONE_EDGE, via=[(285, 352), (285, 495)], label='9-byte packet, 10 Hz, BLE\nneutral when unsure', label_dx=-110, label_dy=-72)

    f.group(300, 70, 330, 500, 'On the phone, always')
    f.box(320, 90, 290, 72, 'Assistant tools', ('find_target · where_is · venue_info', 'start_directions · get_status · stop'))
    f.box(320, 182, 290, 86, 'Local detectors', ('EXIT text · door shapes · people', 'Core ML objects · hand signs', 'the Where-is fallback'))
    f.box(320, 288, 290, 86, 'Depth to pins', ('floor-calibrated samples → 6 sectors', 'nearest range → 4 distance rows', 'open side: which way has more room'))
    f.box(320, 394, 290, 86, 'Offline stores', ('venue pack (hashed, expiring)', 'floor grid + route arrows', 'confirmed finds (pending)'))

    f.group(660, 70, 460, 500, 'When connected')
    f.box(680, 90, 240, 72, 'OpenAI Realtime', ('voice in and out, direct;', 'tool calls return to the phone'), fill=CLOUD, edge=CLOUD_EDGE)
    f.box(680, 182, 240, 86, 'Chalk Model Gateway', ('vision model, restricted key', 'one photo + question → {found, box}', 'trace content logging off'), fill=CHALK, edge=CHALK_EDGE)
    f.box(940, 182, 160, 86, 'Chalk evaluations', ('task + 3 scorers', 'metrics with denominators', 'local or hosted runs'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(680, 300, 240, 100, 'Chalk features', ('ObjectHistory: last confirmed find,', 'the sentence to say', 'Venue: pack from reviewed rows', 'named queries last_seen · venue_pack'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(940, 312, 160, 76, 'Postgres', ('Supabase', 'confirmed_finds · venues'), fill=CLOUD, edge=CLOUD_EDGE, small=True)
    f.arrow(610, 126, 680, 126, color=MUTED, label='audio + tool calls', label_dy=-8)
    f.arrow(610, 214, 680, 214, color=CHALK_EDGE, label='JPEG ≤ 1024 px', label_dy=-8)
    f.arrow(680, 246, 610, 246, color=CHALK_EDGE, label='box or not found, 12 s', label_dy=16)
    f.arrow(940, 225, 920, 225, color=CHALK_EDGE, dashed=True, label='picks the model', label_dx=0, label_dy=-10)
    f.arrow(940, 350, 920, 350, color=CHALK_EDGE, label='data source', label_dy=-8)
    f.arrow(680, 372, 610, 437, color=CHALK_EDGE, via=[(645, 372), (645, 437)], label='sentence · pack', label_dy=-8)
    f.arrow(610, 460, 1020, 460, color=MUTED, via=[(1020, 460)], label='"found it" → REST insert, user JWT', label_dy=-8)
    f.arrow(1020, 460, 1020, 388, color=MUTED)
    f.note(20, 590, 'Solid arrows exist in the repository and run against the live database. The dashed one is inside the gateway. Pins never come from the cloud.', size=10.5)
    return f


def where_is() -> Figure:
    f = Figure(1100, 430, 'One Where-is request: through the Model Gateway, or the phone alone',
               'A spoken Where-is question becomes one photo through the Chalk Model Gateway, validated on the phone and placed with LiDAR depth; any failure within the shared 12 second deadline falls back to on-device detectors on the same placement path.')
    y = 80
    f.box(20, y, 130, 72, 'Spoken ask', ('"where is', 'the desk?"'))
    f.box(170, y, 150, 72, 'Snapshot', ('JPEG ≤ 1024 px, q 0.6', 'depth + pose, kept in RAM'))
    f.box(340, y, 220, 72, 'Chalk Model Gateway', ('POST /chat/completions', 'restricted key · X-Chalk-Env-Id', 'FEEL_CHALK_MODEL picks the model'), fill=CHALK, edge=CHALK_EDGE)
    f.box(580, y, 160, 72, 'Reply contract', ('{found, label,', 'box, confidence}', 'or not found'), fill=CHALK, edge=CHALK_EDGE)
    f.box(760, y, 170, 72, 'Phone validates', ('parse · deadline · world epoch', 'tracking · request ownership'))
    f.box(950, y, 130, 72, 'Held target', ('depth at box centre', 'pins + spoken line'), accent=True)
    f.arrow(150, y + 36, 170, y + 36)
    f.arrow(320, y + 36, 340, y + 36, color=CHALK_EDGE)
    f.arrow(560, y + 36, 580, y + 36, color=CHALK_EDGE)
    f.arrow(740, y + 36, 760, y + 36, color=CHALK_EDGE)
    f.arrow(930, y + 36, 950, y + 36)
    f.parts.append(f'<path d="M 340 62 L 340 54 L 740 54 L 740 62" fill="none" stroke="{CHALK_EDGE}" stroke-width="1.2"/>')
    f.note(540, 50, 'one absolute 12 s deadline, shared by phone and evaluation (protocol/where-is-cases.json)', color=CHALK_EDGE, anchor='middle', size=10.5)

    fy = 250
    f.box(340, fy, 400, 86, 'On-device fallback', ('Vision text for EXIT · rectangles for doors · people', 'bundled Core ML detector for chairs and common objects', 'same JSON contract, same placement'), fill=PHONE)
    f.arrow(450, 152, 450, 250, color=MUTED, dashed=True, label='no setup · transport error\nmalformed reply · deadline passed', label_dx=118, label_dy=0)
    f.arrow(740, 293, 845, 152, color=MUTED, dashed=True, via=[(845, 293)], label='fallback result', label_dx=52, label_dy=0)
    f.box(20, fy, 290, 86, 'What never happens', ('no photo is stored or sent anywhere else', 'a valid "not found" does not trigger the fallback', 'a found box is a direction, not a clear path'), fill=PAPER, edge=MUTED, small=True)
    f.note(20, 400, 'Snapshot and placement are local; the gateway round trip is the only network hop. A gateway failure is named in the status next to the fallback result.', size=10.5)
    return f


def evaluation() -> Figure:
    f = Figure(1040, 520, 'The evaluation loop: identical inputs, explicit denominators, a model picked by evidence',
               'Labeled photos pass a local preflight, run either locally through the gateway or as a hosted Chalk evaluation with three scorers, and produce one report with per-metric denominators that selects the gateway model.')
    f.box(20, 70, 230, 70, 'Consented photos + labels', ('labels.jsonl: image, question, box', 'at least one third absent'))
    f.box(20, 160, 230, 70, 'Synthetic set', ('evals/make_synthetic.py', 'EXIT signs and doors on walls'), fill=PAPER, edge=MUTED)
    f.box(290, 100, 240, 100, 'Preflight, no cloud', ('validate labels, confine image paths', 're-encode as the phone does (≤ 1024 px, q 0.6)', 'SHA-256 of dataset and prompt'))
    f.arrow(250, 105, 290, 140)
    f.arrow(250, 195, 290, 160)
    f.box(570, 70, 220, 76, 'Local run  --local', ('task + scorers on this Mac', 'each row through the gateway'), fill=CHALK, edge=CHALK_EDGE)
    f.box(570, 164, 220, 96, 'Hosted run', ('upload dataset · deploy task', 'and scorers · evaluation run', 'result dataset by run ID'), fill=CHALK, edge=CHALK_EDGE)
    f.arrow(530, 140, 570, 108, color=CHALK_EDGE)
    f.arrow(530, 160, 570, 212, color=CHALK_EDGE)
    f.box(830, 70, 190, 190, 'Three scorers', ('points_correctly', 'box centre inside the label,', 'or absent and "not found"', '', 'reply_is_well_formed', 'obeys the JSON contract', '', 'false_found', 'absent, yet claimed seen'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.arrow(790, 108, 830, 108, color=CHALK_EDGE)
    f.arrow(790, 212, 830, 212, color=CHALK_EDGE)
    f.box(290, 300, 500, 110, 'One report shape for both runs', ('present localization · absent accuracy · false found · well-formed · missing response,', 'each as numerator / denominator', 'latency p50 · p95 · max, token usage, resolved model, run and dataset IDs', 'no photo, question, reply or provider text is retained'), accent=True)
    f.arrow(680, 146, 680, 164, color=CHALK_EDGE)
    f.arrow(680, 260, 680, 300, color=CHALK_EDGE, label='rows + scores', label_dx=52)
    f.box(830, 300, 190, 110, 'Pick the model', ('reject unsafe first:', 'false found on absent rows', 'then speed and cost', 'among the acceptable'), fill=PAPER, edge=MUTED)
    f.arrow(790, 355, 830, 355)
    f.box(830, 440, 190, 50, 'FEEL_CHALK_MODEL', ('the phone and both runs read it',), small=True)
    f.arrow(925, 410, 925, 440)
    f.arrow(830, 465, 130, 465, color=MUTED, dashed=True, label='a prompt or model change reruns the same labels', label_dy=-8)
    f.arrow(130, 465, 130, 230, color=MUTED, dashed=True)
    f.note(20, 508, 'Execution success is not a quality pass: the report says NOT_ASSESSED until a person reads the scores. Synthetic rows prove the pipeline, not a model.', size=10.5)
    return f


def context() -> Figure:
    f = Figure(1100, 560, 'Memory and venue knowledge: Postgres rows become Chalk features the assistant can say',
               'The phone writes confirmed finds to Supabase Postgres; Chalk reads the same tables as a data source, resolves the latest find per object into a spoken sentence and builds venue packs from reviewed entries; named queries serve both to the assistant, and packs are answered offline on the phone.')
    f.group(20, 70, 230, 460, 'Phone')
    f.box(40, 90, 190, 80, '"Found it"', ('after Where-is or a finder', 'pointed at the thing'), accent=True)
    f.box(40, 200, 190, 80, 'Write a find', ('Supabase REST, user JWT', 'row-level security: own rows'), fill=PAPER, edge=MUTED, dashed=True)
    f.box(40, 330, 190, 80, 'Ask', ('"where did I last', 'see my keys?"'))
    f.box(40, 440, 190, 70, 'Venue pack store', ('answers without internet', 'hash-checked, expires'))
    f.arrow(135, 170, 135, 200, color=MUTED, dashed=True)

    f.group(290, 70, 220, 460, 'Supabase Postgres')
    f.box(310, 150, 180, 70, 'confirmed_finds', ('user_id · object_name', 'place · confidence · found_at'), fill=CLOUD, edge=CLOUD_EDGE)
    f.box(310, 300, 180, 90, 'venues · venue_entries', ('reviewed HTTPS sources', 'effective dates, restrictions', 'sql/schema.sql · sql/seed.sql'), fill=CLOUD, edge=CLOUD_EDGE)
    f.arrow(230, 240, 310, 185, color=MUTED, dashed=True, label='insert', label_dy=-6)

    f.group(550, 70, 300, 460, 'Chalk (chalk/feel_context)')
    f.box(570, 90, 260, 54, 'Data source "feel_finds"', ('PostgreSQL · credentials stay in Chalk',), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(570, 164, 260, 100, 'Find → ObjectHistory', ('finds_of_history: SQL by "<user>:<object>"', 'last_find: the latest confirmed find wins', 'spoken_history(Now): relative time,', 'never a present-tense claim'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(570, 284, 260, 86, 'VenueEntry → Venue.pack', ('venue_row · venue_entries: SQL', 'build_pack: feel_chalk.venue_pack.build,', 'byte-identical to the local builder'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(570, 390, 260, 60, 'Named queries', ('last_seen · venue_pack', 'inputs and outputs pinned at deploy'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(570, 470, 260, 48, 'ScheduledQuery: daily packs', ('planned',), fill=PAPER, edge=MUTED, dashed=True, small=True)
    f.arrow(490, 185, 570, 214, color=CHALK_EDGE)
    f.arrow(490, 345, 570, 327, color=CHALK_EDGE)
    f.arrow(700, 144, 700, 164, color=CHALK_EDGE)
    f.arrow(700, 264, 700, 284, color=CHALK_EDGE)
    f.arrow(700, 370, 700, 390, color=CHALK_EDGE)

    f.group(890, 70, 190, 460, 'Served')
    f.box(905, 150, 160, 100, 'Service token', ('CHALK_CLIENT_ID + SECRET,', 'scoped to one environment', 'feel_chalk.context today,', 'the phone next'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(905, 290, 160, 90, 'Assistant says', ('"Keys: last confirmed at', 'the kitchen table,', '2 hours ago."'), accent=True, small=True)
    f.box(905, 410, 160, 70, 'Pack download', ('{schema, sha256,', 'payload}'), small=True)
    f.arrow(830, 420, 905, 200, color=CHALK_EDGE, via=[(858, 420), (858, 200)], label='POST /v1/query', label_dx=0, label_dy=-6)
    f.arrow(985, 250, 985, 290, color=CHALK_EDGE)
    f.arrow(985, 380, 985, 410, color=CHALK_EDGE)
    f.arrow(905, 445, 230, 475, color=MUTED, dashed=True, via=[(882, 445), (882, 475)], label='HTTPS, when connected', label_dx=-382, label_dy=-6)
    f.arrow(230, 370, 905, 335, color=MUTED, dashed=True, via=[(270, 370), (270, 548), (870, 548), (870, 335)], label='planned: last_seen tool on the phone', label_dx=-150, label_dy=-6)
    return f


def sensing() -> Figure:
    f = Figure(1040, 470, 'Sensing to pins, with the open-side finder and the direction cues',
               'LiDAR depth becomes seven sector ranges and four distance rows sent to the pins at 10 Hz; alongside, the open-side finder names which side has more room with hysteresis and urgency, and route arrows play as cues that close obstacles always override.')
    y = 80
    f.box(20, y, 150, 76, 'LiDAR depth', ('ARKit sceneDepth', 'with confidence'))
    f.box(190, y, 170, 76, 'Floor-calibrated samples', ('measured camera height', 'keep 0.6 to 2.1 m above floor'))
    f.box(380, y, 170, 76, 'Seven sectors', ('nearest range per 12.9°', 'unknown stays unknown'))
    f.box(570, y, 170, 76, 'Four rows', ('< 0.9 · < 1.6 · < 2.5 · ≤ 4 m', 'target column highlighted'))
    f.box(760, y, 120, 76, '9-byte packet', ('sequence, bands,', 'highlight'))
    f.box(900, y, 120, 76, 'Pins', ('BLE, 10 Hz', '7 × 4'), accent=True)
    for x1, x2 in ((170, 190), (360, 380), (550, 570), (740, 760), (880, 900)):
        f.arrow(x1, y + 38, x2, y + 38)
    f.note(20, 180, 'The pins always come from live depth. Nothing below replaces them; cues are held back while any pin is within 0.9 m.', color=ACCENT, size=11)

    oy = 215
    f.box(20, oy, 330, 110, 'Open-side finder, from the seven ranges', ('width filter: a column has the room of its narrower neighbour', 'smoothing 0.6 s · most room wins · 0.4 m switch margin', 'urgency from the range ahead (1.6 m → 0.3 m)', 'unknown never counts as room; the result is relative'))
    f.arrow(465, 156, 465, 215)
    f.arrow(350, 270, 390, 270)
    f.box(390, oy, 250, 110, 'Says and taps', ('"An obstacle was 0.8 meters ahead.', 'More room to your left."', 'one sweep cue toward that column', '(arrows on, nothing closer than 0.9 m)'), accent=True)
    f.box(680, oy, 340, 110, 'Direction arrows', ('floor grid from depth · A* route to the target', 'DirectionCue: straight, bear, turn, arrived', 'CuePlayer draws it on the pins for 100 ms per frame,', 'holds while anything is within 0.9 m'))
    f.arrow(660, 156, 850, 215, color=MUTED, label='target + pose', label_dx=50, label_dy=-6)
    f.arrow(640, 270, 680, 270, color=MUTED, dashed=True, label='same cue player', label_dy=-8)
    f.box(20, 350, 1000, 86, 'Where the inputs come from', ('target: a finder (door, exit, chair, person, teammate) or a held Where-is result', 'route goal: a Where-is target, two fingers on a column, or a V sign', 'voice: notices are throttled and must still match the scene when spoken; muting keeps commands working'), fill=PAPER, edge=MUTED, small=True)
    f.note(20, 458, 'Memory (Chalk) can shortcut the question, never the pins: a remembered target gives a direction to route toward, while the live rows show what is there now.', size=10.5)
    return f


def room_memory() -> Figure:
    f = Figure(1100, 560, 'Room memory: a printed tag gives the room a frame, so a remembered target answers before any photo',
               'A printed FEEL tag recognized by ARKit image detection gives the room a coordinate frame; targets the user confirmed earlier are stored in that frame on the phone and, when shared, aggregated by Chalk, so a later where-is question points the pins at once while the photo path stays one word away.')
    f.group(20, 70, 680, 460, 'Phone')
    f.box(40, 90, 200, 86, 'Printed FEEL tag', ('feel-tag-01, printed 20 cm wide', 'ARKit image detection', 'frame within about a second'))
    f.box(270, 90, 200, 86, 'Tag frame', ('x right · y out · z down', 'world ↔ tag coordinates', 'bound to one world epoch'))
    f.box(500, 90, 180, 86, 'Local anchors', ('JSON per tag id', 'Application Support', 'newest 200 kept'))
    f.arrow(240, 133, 270, 133)
    f.arrow(470, 133, 500, 133)
    f.box(40, 220, 200, 70, '"Where is the exit?"', ('tag seen this session?', 'label remembered here?'), accent=True)
    f.box(270, 212, 200, 86, 'Remembered place', ('median of the last 20', 'sightings for that label,', 'in this world only'))
    f.arrow(240, 255, 270, 255)
    f.arrow(590, 176, 590, 212, label='anchors for this tag', label_dx=68, label_dy=4)
    f.box(500, 212, 180, 100, 'Held target from memory', ('pins point there at once', '"Last time the exit was about', '2 meters ahead to your left.', 'Say photo to check again."'), accent=True)
    f.arrow(470, 255, 500, 255, label='hit', label_dy=-8)
    f.box(500, 340, 180, 86, 'Where-is photo path', ('no memory, or "photo"', 'gateway or on-device, 2–12 s', 'same held-target code'), fill=PAPER, edge=MUTED)
    f.arrow(370, 298, 500, 383, color=MUTED, via=[(370, 383)], label='miss · "photo"', label_dx=0, label_dy=-6)
    f.box(40, 430, 200, 70, 'Confirmed find', ('"found it" · arrival at the target', 'target → tag frame → anchor'))
    f.arrow(240, 465, 590, 176, color=MUTED, via=[(690, 465), (690, 140)], label='append', label_dx=-28, label_dy=-6)
    f.box(270, 430, 200, 70, 'get_status: room_memory', ('tag · remembered labels', 'hits · misses'), small=True)

    f.group(740, 70, 340, 460, 'Chalk: shared memory')
    f.box(760, 90, 300, 70, 'anchors table', ('Supabase Postgres, shared = true only', 'user · venue · tag · label · x y z · seen_at'), fill=CLOUD, edge=CLOUD_EDGE, small=True)
    f.box(760, 190, 300, 100, 'Anchor → RoomMemory', ('key "<venue>:<tag>"', 'per label: median of the last 20,', 'sighting count, last seen', 'feel_chalk/anchors.py, as on the phone'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(760, 320, 300, 54, 'Named query room_anchors', ('spoken · targets · count · last_seen_at',), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(760, 404, 300, 86, 'Assistant says', ('"Remembered here: exit about 6 meters', 'ahead-right, seen 4 times, last 2 hours ago."', 'directions as seen from the tag'), accent=True, small=True)
    f.arrow(910, 160, 910, 190, color=CHALK_EDGE)
    f.arrow(910, 290, 910, 320, color=CHALK_EDGE)
    f.arrow(910, 374, 910, 404, color=CHALK_EDGE)
    f.arrow(680, 112, 760, 112, color=MUTED, label='REST insert, user JWT,\nshared unless turned off', label_dx=0, label_dy=-22)
    f.arrow(760, 347, 720, 347, color=MUTED, dashed=True)
    f.arrow(720, 347, 680, 160, color=MUTED, dashed=True, via=[(720, 160)], label='download (planned)', label_dx=-50, label_dy=-6)
    f.note(20, 548, 'The pins always come from live depth: memory replaces the photo round trip, never the rows. A tracking reset drops the tag frame and the held target together.', color=ACCENT, size=10.5)
    return f


def room_structure() -> Figure:
    f = Figure(1100, 590, 'Room structure memory: the floor grid a visit learned comes back as a prior for the route planner',
               'With a printed tag in view, the floor grid a session learned is exported into the tag frame when sensing stops or tracking resets and kept per tag as one visit; the first sighting of the tag on a later visit seeds the planner with the per-cell merge of the stored visits, so route arrows can head for a remembered place before the camera has seen the room, while live observations override the prior cell by cell and the pins read only live depth. Chalk merges shared visits by the same vote.')
    f.group(20, 70, 680, 480, 'Phone')
    f.box(40, 90, 200, 86, 'Floor grid, this session', ('LiDAR points → 10 cm cells', 'free · blocked · unknown', 'A* routes for the arrows'))
    f.box(270, 90, 200, 86, 'Stop or tracking reset', ('the grid is about to go:', 'export the cells seen into', "the tag's levelled frame"))
    f.box(500, 90, 180, 86, 'Visit map (RoomMap)', ('cell size · origin · size', 'cells 28f2b10f2u6b…', 'newest 10 per tag on disk'))
    f.arrow(240, 133, 270, 133)
    f.arrow(470, 133, 500, 133)
    f.box(40, 230, 200, 86, 'Next visit: tag seen', ('first sighting in this world', 'ARKit image detection', 'frame bound to the world'), accent=True)
    f.box(270, 230, 200, 86, 'Merge of the visits', ('per cell: blocked when ≥ half', 'of the visits that saw it did,', 'free otherwise, else unknown'))
    f.box(500, 230, 180, 86, 'Prior in the new grid', ('fills cells the camera has', 'not classified yet; every live', 'classification overrides it'))
    f.arrow(240, 273, 270, 273)
    f.arrow(470, 273, 500, 273)
    f.arrow(590, 176, 370, 230, color=MUTED, via=[(590, 203), (370, 203)], label='stored visits', label_dx=0, label_dy=-6)
    f.box(40, 370, 320, 100, 'Arrows before the room is seen', ('"where is the exit": remembered anchor → route goal', 'A* around remembered walls → one arrow,', 'a suggested direction, never a clear path', 'a tracking reset drops prior and goal together'), accent=True)
    f.arrow(590, 316, 200, 370, color=ACCENT, via=[(590, 343), (200, 343)])
    f.box(390, 370, 290, 100, 'get_status: room_structure', ('tag · visits · cells · blocked · seeded', 'a session counts as a visit only after', 'the camera classified 20 cells', 'live depth drives the pins; memory seeds routes'), small=True)
    f.note(40, 505, 'A different print size or a tag lying flat gives no map: the frame must be upright on a wall (RoomFrame.levelled), 20 cm wide as drawn.', size=10.5)

    f.group(740, 70, 340, 480, 'Chalk: shared structure')
    f.box(760, 90, 300, 70, 'room_maps table', ('Supabase Postgres, shared = true only', 'user · venue · tag · cell size · origin · cells'), fill=CLOUD, edge=CLOUD_EDGE, small=True)
    f.box(760, 190, 300, 100, 'RoomMap → RoomMemory.structure', ('key "<venue>:<tag>", newest 50 visits', 'the same per-cell vote as the phone', 'feel_chalk/room_map.py', 'protocol/room-map-v1.json pins both'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(760, 320, 300, 54, 'Named query room_structure', ('structure · structure_visits',), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.box(760, 404, 300, 86, 'context.py room-structure', ('"8 x 6 cells of 0.1 m, 46 remembered', '(38 free, 8 blocked), merged from 3 visits."', 'writes the merged map as JSON'), fill=CHALK, edge=CHALK_EDGE, small=True)
    f.arrow(910, 160, 910, 190, color=CHALK_EDGE)
    f.arrow(910, 290, 910, 320, color=CHALK_EDGE)
    f.arrow(910, 374, 910, 404, color=CHALK_EDGE)
    f.arrow(680, 112, 760, 112, color=MUTED, label='REST insert, user JWT', label_dx=0, label_dy=-10)
    f.arrow(760, 347, 720, 347, color=MUTED, dashed=True)
    f.arrow(720, 347, 680, 273, color=MUTED, dashed=True, via=[(720, 273)])
    f.note(20, 564, 'The upload of a visit is wired (RoomMemory.uploader, SupabaseWriter). Dashed: the download of the merged map (RoomMemory.fetchSharedStructure), not wired yet. No device test yet.', size=10.5)
    f.note(20, 582, 'The pins always come from live depth. A remembered wall is only a reason for the planner to prefer another way; what the camera sees this session wins cell by cell.', color=ACCENT, size=10.5)
    return f


def chalk_overview() -> Figure:
    f = Figure(1040, 420, 'What Chalk does for the app',
               'Three short stories: a photo question answered through the Chalk Model Gateway and shown on the pins; a confirmed find kept in Chalk memory and answered on the next visit; every model or prompt change scored by Chalk evaluations before it goes live. Obstacles are sensed on the phone alone.')
    cols = [
        ('"Where is the water fountain?"', ('one photo from the phone on the chest',),
         'Chalk Model Gateway', ('a vision model finds it', 'in the photo'),
         'Pins point the way', ()),
        ('"Found it"', ('the user confirms',),
         'Chalk Memory', ('remembers where things were', 'and when'),
         'Next visit', ('"Last seen here, 2 hours ago."', 'pins point there at once')),
        ('Every change', ('same photos, same questions',),
         'Chalk Evals', ('scores each model and prompt', 'misses and false finds first'),
         'The better one goes live', ()),
    ]
    for i, (top, top_lines, mid, mid_lines, bottom, bottom_lines) in enumerate(cols):
        x = 20 + i * 350
        f.box(x, 70, 320, 62, top, top_lines)
        f.arrow(x + 160, 132, x + 160, 180)
        f.box(x, 180, 320, 76, mid, mid_lines, fill=CHALK, edge=CHALK_EDGE)
        f.arrow(x + 160, 256, x + 160, 304, color=CHALK_EDGE)
        f.box(x, 304, 320, 66, bottom, bottom_lines, accent=True)
    f.note(20, 404, 'Obstacles are sensed on the phone alone; nothing from Chalk ever drives the pins directly.', size=11)
    return f


if __name__ == '__main__':
    for build, name in ((system, 'feel-system.svg'), (where_is, 'where-is-path.svg'), (evaluation, 'chalk-eval-loop.svg'),
                        (context, 'chalk-context.svg'), (sensing, 'sensing-to-pins.svg'), (chalk_overview, 'chalk-overview.svg'), (room_memory, 'room-memory.svg'),
                        (room_structure, 'room-structure.svg')):
        print(build().save(name))
