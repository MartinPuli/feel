# Documentation and open contract questions

Official references consulted October 16, 2026:

- [GitHub Actions workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax): event filters, jobs, timeouts and permissions.
- [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use): minimal token permissions and full commit SHA pinning. The checkout v4.2.2 tag was resolved through GitHub's API to `11bd71901bbe5b1630ceea73d27597364c9af683`.
- [GitHub repository contents API](https://docs.github.com/en/rest/repos/contents): creation of the initial README in the empty repository. Later changes use a separate branch.
- [PlatformIO testing](https://docs.platformio.org/en/latest/advanced/unit-testing/index.html): host execution and device execution are distinct. No board execution occurred here.
- [OpenSCAD documentation](https://openscad.org/documentation.html): original parametric source and build scripts are needed for geometry checks. OpenSCAD is installed; the geometry is absent.
- Apple [AR frame timestamp](https://developer.apple.com/documentation/arkit/arframe/timestamp), [tracking state](https://developer.apple.com/documentation/arkit/arcamera/trackingstate-swift.enum), and [BLE writes](https://developer.apple.com/documentation/corebluetooth/cbperipheral/writevalue(_:for:type:)): official entry points were reached, but content extraction encountered JavaScript/Markdown retrieval errors. These are follow-up references, **not** claims of a completed Apple API audit.

The actual source and pinned versions must determine implementation decisions. No unreviewed third-party skills or hooks were installed. Specialized work here consisted of bounded engineering agents and an independent code review; no unavailable `feel-*` skill is claimed to have run.

## Questions the missing protocol/source must settle

| Topic | Known from v7 | Still unresolved |
|---|---|---|
| Wire format | Nine bytes: sequence, seven 0–4 bands, highlight 0–6 or 255 | Exact invalid-write and sequence acceptance policy |
| Loss of input | 500 ms failsafe | Exact boundary, loop latency, disconnect neutralization and time source |
| Cam | Band angles 0, 58, 117, 175 degrees; intermediate gaps; 21-degree tap toward gap | Exact zero/neutral selection, movement timing, offsets, servo limits, intermediate activation |
| Depth | Four nominal intervals 0.3–0.9 / 0.9–1.6 / 1.6–2.5 / 2.5–4 m | Shared endpoint assignment, values closer than 0.3 m, confidence thresholds, stale-frame limits |
| Directions | Seven columns | Field of view, column handedness, angular edge convention, phone mount |
| Targets | Door/EXIT/chair/person/optional teammate | Confidence and lifetime policy, tie arbitration, target behind camera, missing depth |
| Integrity | All nine bytes already assigned | No application checksum/timestamp is described; valid-looking corruption and delayed valid packets cannot be inferred from payload alone |

The simulator documents its assumptions separately. Do not adopt them into production merely because their reference tests pass. BLE has transport-layer protections; the injection tests deliberately operate at the application-packet boundary and do not characterize radio reliability.
