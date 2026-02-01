#!/bin/sh
case "$1" in
    install)
      if ! command -v tree-sitter >/dev/null 2>&1; then 
        case $OS in
          Darwin) echo syspkgmgr:treesitter-cli ;;
          *) echo syspkgmgr:treesitter ;;
        esac
      fi
    ;; 
esac
