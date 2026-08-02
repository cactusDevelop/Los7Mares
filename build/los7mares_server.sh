#!/bin/sh
printf '\033c\033]0;%s\a' Los 7 Mares
base_path="$(dirname "$(realpath "$0")")"
"$base_path/los7mares_server.arm32" "$@"
