# Execution notes

These logs came from the dirty greenfield working tree above preparation commit 97d6d2631b9e37ab7dbb5d3059453bd41855e046. The enclosing V1 commit captures the source.

Final sequential runner: 14 PASS, Apple platform BLOCKED (no xcodegen/xcodebuild/xcrun). Exit 2 intentionally records that limitation. Physical hardware NOT VERIFIED.

An earlier run found PlatformIO outside PATH and failed when two CAD exports shared output. That run is not the pass evidence. PATH was corrected, CAD output locking and unique temporary files were added, a lock regression passed, and the final complete runner passed all available checks.

Linux Swift uses SWIFT_USE_OLD_DRIVER=1, a private libncurses6 and direct XCTest via test_portable.sh because this host restricts child /proc monitoring. No assertions were skipped.

The final 24-file STL manifest hashes were independently rechecked. Source presence is not a behavioral test.
