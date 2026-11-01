#!/bin/bash
exec /bin/bash "$(cd -- "$(dirname -- "$0")" && pwd)/scripts/uninstall.sh" "$@"
