#!/usr/bin/env sh

case "$1" in
  install) echo "uv:python:--default" ;;
  config)
    mkdir -p ~/monty
    uv venv --directory ~/monty --allow-existing --prompt monty
    uv pip install --directory ~/monty -r ~/.config/python/monty
    ;;
esac
