#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/snapnest-launcher-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc Sources/ShituCore/LauncherSearch.swift Tests/LauncherChecks/main.swift -o "$check_dir/checks"
"$check_dir/checks"
