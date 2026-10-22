#!/bin/bash
set -euo pipefail
MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.deskassit.desktop.json"
DEST="$HOME/Library/Application Support/DeskAssit"
rm -f "$MANIFEST" "$DEST/deskassit-native" "$DEST/allowed-extension.txt" "$DEST/selection.json" "$DEST/search-folders.json"
rmdir "$DEST" 2>/dev/null || true
echo "GentleDesk 本机连接与授权目录记录已移除。桌面原文件未被改动。"
