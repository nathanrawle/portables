#!/bin/sh
case "$1" in
    install) command -v mmdc >/dev/null 2&>1 || echo npm:mermaid ;;
esac
