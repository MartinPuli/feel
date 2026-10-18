## October 17 — six-column layout

This version keeps its features and uses six active columns, GPIO32 unused.
See [evidence](evidence/six-columns-20261017/REPORT.md). Physical integration
remains unverified; historical seven-column guidance below is superseded.

# Current voice synchronization

See [VERSION-VOICE-SYNC.md](VERSION-VOICE-SYNC.md) for the current integration.
The following records describe earlier revisions. No V3 phone installation is claimed.

# FEEL V3 — current integration

V3 integrates V1 main `b780519` through updated V2, retaining explicit voice
commands, saved maps, adaptive highlights and barcode finding.

Current validation is recorded in [V3-MAIN-INTEGRATION.md](V3-MAIN-INTEGRATION.md).
Local software validation PASS: 90 portable tests, all three replay suites,
24 app tests, 9 Lantern UI tests, 2 Beacon UI tests, and both unsigned device
builds passed. Physical validation remains pending.

Earlier V3 evidence is retained in [RELEASE-STATUS-V3-PREVIOUS.md](RELEASE-STATUS-V3-PREVIOUS.md).
Those results apply to their recorded commits, not this integration.

The [version guide](VERSIONS.md) explains all three branches. Physical hardware
validation remains pending. This integration neither flashes a board nor installs
an app on the phone. Seven-servo deployment requires the measurement records
described in [SEVEN-SERVO-PRODUCTION.md](SEVEN-SERVO-PRODUCTION.md).
