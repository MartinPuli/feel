#!/bin/sh
set -eu
firmware_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$firmware_dir/build"
compiler=${CXX:-c++}
"$compiler" -std=c++11 -Wall -Wextra -Werror -Wpedantic -O2 \
  -I "$firmware_dir/include" "$firmware_dir/src/controller.cpp" \
  "$firmware_dir/src/commands.cpp" "$firmware_dir/test/controller_tests.cpp" \
  -o "$firmware_dir/build/feel-tests"
"$firmware_dir/build/feel-tests"
"$compiler" -std=c++11 -Wall -Wextra -Werror -Wpedantic -O2 \
  -I "$firmware_dir/include" "$firmware_dir/src/controller.cpp" \
  "$firmware_dir/src/commands.cpp" "$firmware_dir/host/simulator.cpp" \
  -o "$firmware_dir/build/feel-sim"
python3 "$firmware_dir/test/test_cli.py" "$firmware_dir/build/feel-sim"
python3 "$firmware_dir/test/test_board_config.py"
python3 "$firmware_dir/test/test_compile_only_guard.py"
python3 "$firmware_dir/test/test_bench_validation.py"

"$compiler" -std=c++11 -Wall -Wextra -Werror -Wpedantic -O2 \
  -I "$firmware_dir/include" "$firmware_dir/src/controller.cpp" \
  "$firmware_dir/test/single_demo_tests.cpp" -o "$firmware_dir/build/single-demo-tests"
"$firmware_dir/build/single-demo-tests"
