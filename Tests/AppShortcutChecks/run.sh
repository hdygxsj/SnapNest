#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/snapnest-app-shortcuts.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc -parse-as-library Sources/Shitu/HotKey.swift Sources/Shitu/AppShortcuts.swift Tests/AppShortcutChecks/main.swift -o "$check_dir/checks"
"$check_dir/checks"
