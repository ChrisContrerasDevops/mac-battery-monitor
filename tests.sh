#!/bin/bash
exec /bin/bash "$(cd -- "$(dirname -- "$0")" && pwd)/tests/run.sh" "$@"
