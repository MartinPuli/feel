#!/usr/bin/env python3
"""Run offline deterministic FEEL fixtures; render a trace, not another model."""

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import sys

if __package__:
    from .feel_model import ModelConfig, InputPolicy, ReceiverModel, encode_synthetic_frame, integer
else:
    from feel_model import ModelConfig, InputPolicy, ReceiverModel, encode_synthetic_frame, integer

FIXTURES = Path(__file__).parent / "fixtures" / "scenarios.json"


def require_text(value, context):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{context} must be a nonempty string")


def validate_expectation(expected, context="expect"):
    """Never allow vacuous success from {} or recursively empty mappings."""
    if not isinstance(expected, dict) or not expected:
        raise ValueError(f"{context} must contain at least one assertion")
    for key, wanted in expected.items():
        require_text(key, f"{context} key")
        if isinstance(wanted, dict):
            validate_expectation(wanted, f"{context}.{key}")


def validate_scenario(scenario):
    if not isinstance(scenario, dict):
        raise ValueError("scenario must be an object")
    require_text(scenario.get("id"), "scenario id")
    require_text(scenario.get("description"), "scenario description")
    events = scenario.get("events")
    if not isinstance(events, list) or not events:
        raise ValueError(f"{scenario['id']}: events must be a nonempty list")
    previous_ms = 0
    for event in events:
        if not isinstance(event, dict):
            raise ValueError("event must be an object")
        require_text(event.get("label"), "event label")
        time_ms = integer(event.get("time_ms"), "event time_ms")
        if time_ms < previous_ms:
            raise ValueError("fixture event times must be monotonic")
        previous_ms = time_ms
        kind = event.get("kind")
        if kind not in ("packet", "synthetic_frame", "tick", "drop", "connection"):
            raise ValueError(f"unknown fixture event {kind!r}")
        validate_expectation(event.get("expect"))
        if not set(event["expect"]).issubset({"state", "result", "input"}):
            raise ValueError("expect must assert state, result, or input")
        if kind == "packet":
            if not isinstance(event.get("hex"), str):
                raise ValueError("packet hex must be a string, including empty for an invalid-packet test")
            bytes.fromhex(event["hex"])
        elif kind == "connection" and type(event.get("connected")) is not bool:
            raise ValueError("connection event needs a boolean connected field")
        elif kind == "synthetic_frame":
            integer(event.get("seq"), "synthetic sequence", maximum=255)
            if not isinstance(event.get("frame"), dict):
                raise ValueError("synthetic frame must be an object")


def validate_suite(fixture):
    if not isinstance(fixture, dict) or fixture.get("schema_version") != 1:
        raise ValueError("fixture schema_version must be 1")
    integer(fixture.get("seed"), "fixture seed")
    require_text(fixture.get("provenance"), "fixture provenance")
    limits = fixture.get("limitations")
    if not isinstance(limits, list) or not limits:
        raise ValueError("fixture limitations must be a nonempty list")
    for limit in limits:
        require_text(limit, "fixture limitation")
    scenarios = fixture.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        raise ValueError("fixture scenarios must be a nonempty list")
    identifiers = set()
    for scenario in scenarios:
        validate_scenario(scenario)
        if scenario["id"] in identifiers:
            raise ValueError(f"duplicate scenario id {scenario['id']}")
        identifiers.add(scenario["id"])


def compare(expected, actual, prefix=""):
    failures = []
    for key, wanted in expected.items():
        path = f"{prefix}.{key}" if prefix else key
        if key not in actual:
            failures.append(f"{path}: missing")
        elif isinstance(wanted, dict):
            if not isinstance(actual[key], dict):
                failures.append(f"{path}: expected object, got {actual[key]!r}")
            else:
                failures.extend(compare(wanted, actual[key], path))
        elif wanted != actual[key]:
            failures.append(f"{path}: expected {wanted!r}, got {actual[key]!r}")
    return failures


def replay_scenario(scenario):
    validate_scenario(scenario)
    config = ModelConfig(**scenario.get("receiver_policy", {}))
    input_policy = InputPolicy(**scenario.get("input_policy", {}))
    receiver = ReceiverModel(config)
    traces = []
    for event in scenario["events"]:
        now_ms = event["time_ms"]
        kind = event["kind"]
        result, metadata, packet_hex = None, None, None
        if kind == "packet":
            packet_hex = event["hex"]
            result = receiver.receive(bytes.fromhex(packet_hex), now_ms)
        elif kind == "synthetic_frame":
            packet, metadata = encode_synthetic_frame(event["frame"], now_ms,
                                                       event["seq"], input_policy)
            packet_hex = packet.encode().hex()
            result = receiver.receive(packet.encode(), now_ms)
        elif kind == "connection":
            receiver.set_connected(event["connected"], now_ms)
        elif kind in ("tick", "drop"):
            receiver.advance(now_ms)
            if kind == "drop":
                metadata = {"injection": "packet deliberately not delivered"}
        else:
            raise ValueError(f"unknown fixture event {kind!r}")
        snapshot = receiver.snapshot()
        actual = {"state": snapshot, "result": result, "input": metadata}
        failures = compare(event["expect"], actual)
        traces.append({"label": event["label"], "kind": kind, "hex": packet_hex,
                       "synthetic_frame": event.get("frame"), **actual,
                       "expected": event["expect"], "failures": failures,
                       "passed": not failures})
    return {"id": scenario["id"], "description": scenario["description"],
            "receiver_policy": asdict(config), "input_policy": asdict(input_policy),
            "passed": all(t["passed"] for t in traces), "trace": traces}


def run_suite(path=FIXTURES):
    source = Path(path).read_bytes()
    fixture = json.loads(source)
    validate_suite(fixture)
    scenarios = [replay_scenario(s) for s in fixture["scenarios"]]
    return {"mode": "SIMULATION — specification model, not production software",
            "schema_version": 1, "fixture_sha256": hashlib.sha256(source).hexdigest(),
            "seed": fixture["seed"], "fixture_provenance": fixture["provenance"],
            "limitations": fixture["limitations"], "scenario_count": len(scenarios),
            "event_count": sum(len(s["trace"]) for s in scenarios),
            "passed": all(s["passed"] for s in scenarios), "scenarios": scenarios}


HTML_TEMPLATE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>FEEL • SIMULATION replay</title><style>
:root{font-family:system-ui,sans-serif;color:#ecf0f6;background:#10151f;color-scheme:dark}*{box-sizing:border-box}
body{margin:0 auto;max-width:1150px;padding:24px}h1{margin:.3em 0;font-size:2rem}h2{font-size:1.1rem}
.warning{border-left:5px solid #f5bd4f;background:#292218;padding:14px 18px;line-height:1.5}.tag{color:#f5bd4f;font-weight:800;letter-spacing:.09em}
.grid{display:grid;grid-template-columns:minmax(300px,1fr) minmax(300px,1fr);gap:20px;margin:20px 0}.panel{border:1px solid #344154;border-radius:12px;padding:18px;background:#192130}
select,button{font:inherit;padding:10px;border:1px solid #596b85;border-radius:6px;background:#253147;color:white}select{width:100%;margin:8px 0}button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #f5bd4f;outline-offset:3px}button:disabled{opacity:.4}
input[type=range]{width:100%;margin:18px 0}.puck{display:grid;grid-template-columns:repeat(7,1fr);gap:9px;margin:16px 0}.column{display:grid;gap:12px;text-align:center;padding:10px 3px;border:1px solid transparent;border-radius:9px}.column.highlight{border:2px solid #f5bd4f;padding:9px 2px}.pin{aspect-ratio:1;border-radius:50%;background:#29364b;border:2px solid #5c6d83;display:grid;place-items:center;font-size:.8rem}.pin.on{background:#9ddbd0;color:#0d3530;border-color:#d1fff4;font-weight:bold}.orientation{display:flex;justify-content:space-between;color:#bcc8dc;font-size:.9rem}
pre{white-space:pre-wrap;overflow-wrap:anywhere;font-size:.82rem;max-height:430px;overflow:auto}p,li{line-height:1.5}small{color:#b8c4d6}.pass{color:#9ddbd0}.fail{color:#ff9c9c}#eventLabel{min-height:48px}.controls{display:flex;justify-content:space-between;gap:10px}code{overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:.85rem}th,td{text-align:left;border-bottom:1px solid #344154;padding:7px 4px}@media(max-width:760px){body{padding:14px}.grid{grid-template-columns:1fr}.puck{gap:5px}.pin{font-size:.7rem}}
</style></head><body>
<div class="tag">SIMULATION • OFFLINE SPECIFICATION MODEL</div><h1>FEEL packet replay</h1>
<div class="warning"><strong>No physical hardware or production iOS / firmware is connected or verified.</strong> Circles show logical band requests decoded from nine-byte fixtures. Nominal angles are unmeasured commands. They do not show actual pin height, safe mechanical transitions, torque, timing, or working sensing.</div>
<p id="summary"></p><label for="scenario">Choose an asserted scenario</label><select id="scenario"></select>
<p id="description"></p><div class="grid"><section class="panel"><h2>SIMULATION • requested 7 × 4 pattern</h2><div class="orientation"><span>Fingers • band 4</span><span>Yellow outline = highlight request</span></div><div id="puck" class="puck" aria-label="Logical tactile requests"></div><div class="orientation"><span>Wrist • band 1</span><span>Columns 0–6</span></div><p><small>Left / right on screen is illustrative. Real mounting, angle sign, and pin motion remain unverified. Band 0 cannot distinguish clear space from unknown sensing.</small></p><input id="step" type="range" min="0" value="0" aria-label="Simulation trace step"><div class="controls"><button id="previous">Previous step</button><button id="next">Next step</button></div><p id="eventLabel" aria-live="polite"></p><p id="state"></p><p>Packet hex: <code id="packet"></code></p></section>
<section class="panel"><h2>SIMULATION • evidence at this step</h2><p id="assertions"></p><p><small>Highlight is a tap request only. The optional 21° dip hint is nominal; tap cadence, actuation, and physical tapping are not simulated.</small></p><table><thead><tr><th>Column</th><th>Nominal command</th><th>Tap hint</th><th>Reference phase</th></tr></thead><tbody id="commands"></tbody></table><details open><summary>Trace, expected result and policy metadata</summary><pre id="evidence"></pre></details></section></div>
<section class="panel"><h2>Scope and unresolved contract decisions</h2><ul id="limits"></ul><details><summary>Active reference policies and fixture provenance</summary><pre id="policies"></pre></details></section>
<script type="application/json" id="data">__DATA__</script><script>
"use strict";
const report=JSON.parse(document.getElementById("data").textContent);
const el=id=>document.getElementById(id); let scenarioIndex=0, stepIndex=0;
el("summary").textContent=`${report.passed?"PASS":"FAIL"}: ${report.scenario_count} synthetic scenarios, ${report.event_count} asserted steps. Seed ${report.seed}. No production or physical test result is implied.`;
report.scenarios.forEach((s,i)=>{const o=document.createElement("option");o.value=i;o.textContent=`${s.passed?"PASS":"FAIL"} · ${s.id}`;el("scenario").append(o)});
report.limitations.forEach(t=>{const li=document.createElement("li");li.textContent=t;el("limits").append(li)});
function render(){const scenario=report.scenarios[scenarioIndex], row=scenario.trace[stepIndex], state=row.state;
 el("description").textContent=scenario.description;el("step").max=scenario.trace.length-1;el("step").value=stepIndex;
 el("previous").disabled=stepIndex===0;el("next").disabled=stepIndex===scenario.trace.length-1;
 el("eventLabel").textContent=`Step ${stepIndex+1}/${scenario.trace.length}, t=${state.time_ms} ms · ${row.label}`;
 el("state").textContent=`SIMULATION state: ${state.status}. Receipt: ${row.result?row.result.reason:row.kind}.`;
 el("packet").textContent=row.hex===null?"No packet delivered":row.hex||"empty payload";
 el("assertions").textContent=row.passed?"PASS — fixture expectations match this model":"FAIL — "+row.failures.join("; ");el("assertions").className=row.passed?"pass":"fail";
 el("puck").replaceChildren();state.bands.forEach((b,c)=>{const col=document.createElement("div");col.className="column"+(state.highlight===c?" highlight":"");col.setAttribute("aria-label",`Column ${c}, band ${b}${state.highlight===c?", highlighted":""}`);for(let r=4;r>=1;r--){const pin=document.createElement("div");pin.className="pin"+(b===r?" on":"");pin.textContent=b===r?String(r):"·";col.append(pin)}const label=document.createElement("small");label.textContent=c;col.append(label);el("puck").append(col)});
 el("commands").replaceChildren();state.columns.forEach((c,i)=>{const tr=document.createElement("tr");[i,`${c.nominal_command_degrees}°`,c.nominal_tap_dip_degrees===null?"—":`${c.nominal_tap_dip_degrees}°`,c.phase].forEach(v=>{const td=document.createElement("td");td.textContent=v;tr.append(td)});el("commands").append(tr)});
 el("evidence").textContent=JSON.stringify({expected:row.expected,result:row.result,input:row.input,synthetic_frame:row.synthetic_frame,counts:state.counts,failures:row.failures},null,2);
 el("policies").textContent=JSON.stringify({receiver:scenario.receiver_policy,input:scenario.input_policy,seed:report.seed,fixture_sha256:report.fixture_sha256,provenance:report.fixture_provenance},null,2);
}
el("scenario").addEventListener("change",()=>{scenarioIndex=Number(el("scenario").value);stepIndex=0;render()});
el("step").addEventListener("input",()=>{stepIndex=Number(el("step").value);render()});
el("previous").addEventListener("click",()=>{if(stepIndex>0)stepIndex--;render()});el("next").addEventListener("click",()=>{if(stepIndex<report.scenarios[scenarioIndex].trace.length-1)stepIndex++;render()});render();
</script></body></html>'''


def render_html(report):
    # JSON data is untrusted text in HTML: prevent </script> and U+2028/2029.
    encoded = json.dumps(report, ensure_ascii=True, allow_nan=False)
    encoded = encoded.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    return HTML_TEMPLATE.replace("__DATA__", encoded)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, default=FIXTURES)
    parser.add_argument("--output", type=Path, default=Path(".artifacts/simulation"))
    args = parser.parse_args(argv)
    report = run_suite(args.fixtures)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (args.output / "index.html").write_text(render_html(report), encoding="utf-8")
    outcome = "PASS" if report["passed"] else "FAIL"
    print(f"{outcome}: SIMULATION ONLY — {report['scenario_count']} scenarios, {report['event_count']} asserted steps")
    for scenario in report["scenarios"]:
        for step in scenario["trace"]:
            for failure in step["failures"]:
                print(f"FAIL {scenario['id']} / {step['label']}: {failure}")
    print(f"Offline replay: {args.output / 'index.html'}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
