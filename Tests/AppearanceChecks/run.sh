#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/qingyu-appearance.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc -parse-as-library Sources/Shitu/WorkspaceTheme.swift Tests/AppearanceChecks/main.swift -o "$check_dir/checks"
"$check_dir/checks"
