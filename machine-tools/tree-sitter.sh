#!/usr/bin/env bash
case "$1" in
    install)
      if ! command -v tree-sitter >/dev/null 2>&1; then
        echo syspkgmgr:tree-sitter-cli
      fi
    ;;
esac
