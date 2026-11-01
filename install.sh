#!/bin/bash
# Compatibilidad con las instrucciones de versiones anteriores.
exec /bin/bash "$(cd -- "$(dirname -- "$0")" && pwd)/scripts/install.sh" "$@"
