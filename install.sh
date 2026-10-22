#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
EXTENSION_ID="${1:-}"
if ! [[ "$EXTENSION_ID" =~ ^[a-p]{32}$ ]]; then
  printf '%s\n' 'Usage: gentledesk setup <32-letter Chrome extension ID>' >&2
  exit 1
fi
shift
TEST_ROOT=""
if [ "${1:-}" = '--test-root' ] && [ "$#" = 2 ] && [[ "$2" = /* ]]; then TEST_ROOT="$2"; shift 2; fi
if [ "$#" != 0 ]; then printf '%s\n' 'Unknown installation option.' >&2; exit 1; fi
NATIVE_SOURCE='./build/deskassit-native'
if [ ! -f "$NATIVE_SOURCE" ]; then NATIVE_SOURCE='./deskassit-native'; fi
if [ ! -f "$NATIVE_SOURCE" ]; then printf '%s\n' 'Companion binary missing. Re-download the installer.' >&2; exit 1; fi
if [ -n "$TEST_ROOT" ]; then
  DEST="$TEST_ROOT/DeskAssit"
  MANIFEST_DIR="$TEST_ROOT/NativeMessagingHosts"
else
  DEST="$HOME/Library/Application Support/DeskAssit"
  MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
fi
mkdir -p "$DEST" "$MANIFEST_DIR"
chmod 700 "$DEST"
# Install to a new inode, so an active native messaging process is never overwritten in place.
TEMP_BINARY="$(mktemp "$DEST/.native.XXXXXX")"
TEMP_ALLOW="$(mktemp "$DEST/.extension.XXXXXX")"
TEMP_MANIFEST="$(mktemp "$MANIFEST_DIR/.gentledesk.XXXXXX")"
trap 'rm -f "$TEMP_BINARY" "$TEMP_ALLOW" "$TEMP_MANIFEST"' EXIT
cp "$NATIVE_SOURCE" "$TEMP_BINARY"
chmod 700 "$TEMP_BINARY"
printf '%s\n' "$EXTENSION_ID" > "$TEMP_ALLOW"
chmod 600 "$TEMP_ALLOW"
DEST_ESCAPED=$(/usr/bin/osascript -l JavaScript -e 'function run(a){return JSON.stringify(a[0]);}' "$DEST/deskassit-native")
printf '{"name":"com.deskassit.desktop","description":"GentleDesk local desktop companion","path":%s,"type":"stdio","allowed_origins":["chrome-extension://%s/"]}\n' "$DEST_ESCAPED" "$EXTENSION_ID" > "$TEMP_MANIFEST"
chmod 600 "$TEMP_MANIFEST"
mv -f "$TEMP_BINARY" "$DEST/deskassit-native"
mv -f "$TEMP_ALLOW" "$DEST/allowed-extension.txt"
mv -f "$TEMP_MANIFEST" "$MANIFEST_DIR/com.deskassit.desktop.json"
printf '%s\n' 'GentleDesk installed. Return to Chrome and connect your desktop.'
