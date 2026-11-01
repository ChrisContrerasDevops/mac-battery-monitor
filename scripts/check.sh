#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
for script in "$root"/*.sh "$root"/scripts/*.sh "$root"/tests/*.sh; do /bin/bash -n "$script"; done
/bin/bash "$root/tests/run.sh"
/bin/bash "$root/scripts/build.sh"
app="$root/build/Mac Battery Monitor.app"
"$app/Contents/MacOS/MacBatteryMonitor" --self-test
if [ -f "$root/tests/bundle.sh" ]; then /bin/bash "$root/tests/bundle.sh"; fi
