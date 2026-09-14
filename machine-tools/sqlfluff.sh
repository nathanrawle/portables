#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
    install)
        if ! command -v uv >/dev/null 2>&1 || ! uv tool list | grep '^sqlfluff v' >/dev/null; then
            echo uv:sqlfluff
        fi
    ;;
esac
