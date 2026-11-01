#!/bin/bash
exec /bin/bash "$(cd -- "$(dirname -- "$0")" && pwd)/scripts/power-permission.sh" "$@"
