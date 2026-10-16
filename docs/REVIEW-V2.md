# Independent V2 review

A separate read-only reviewer inspected the production memory manager/CLI,
mutations, geometry, app lifecycle and UI; the author integrated changes.

- Fixed memory yaw projection disagreeing with V1 obstacle sectors when the phone
  pitched. Now shares inverse-camera bearing/range, with20°/40° equivalence tests.
- Fixed the memory panel showing raw geometric guidance while the encoder was
  paused for floor calibration. It now displays the blocked encoder state.
- Verified session IDs cannot be reused, failed mutations preserve state, return
  IDs cannot collide, resets clear coordinates, transient lost tracking stops
  guidance, old frames/NI callbacks cannot restore a previous world, finder
  changes stop conflicting recall, and simulation never sends movement to BLE.
- Independently ran58 production-core tests with0 failures. Root separately ran
  the consolidated Swift/firmware/contract suites and the spatial browser view.

No unresolved critical/high defect was found in the reviewed scope. Apple SDK
compilation, simulator execution and physical behavior remain separate gates.
