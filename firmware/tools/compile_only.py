"""PlatformIO software-check environments never upload their fixture binaries."""
from SCons.Errors import UserError
from SCons.Script import COMMAND_LINE_TARGETS

if any("upload" in target or target == "program" for target in COMMAND_LINE_TARGETS):
    raise UserError("FEEL compilecheck uses unmeasured fixture pulse limits and MUST NOT be flashed. Select a normal board environment and configure actual measured limits.")
print("FEEL SOFTWARE COMPILE CHECK ONLY: output path enabled using UNMEASURED test constants; no upload permitted")
