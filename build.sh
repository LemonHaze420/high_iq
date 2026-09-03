#!/usr/bin/env sh
set -eu
mkdir -p build
odin build . -out:build/high_iq "$@"
