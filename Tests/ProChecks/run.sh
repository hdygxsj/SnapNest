#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/qingyu-pro.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swiftc -parse-as-library Sources/Shitu/WorkspaceTheme.swift Sources/Shitu/ProStore.swift Tests/ProChecks/main.swift -o "$check_dir/checks"
"$check_dir/checks"
