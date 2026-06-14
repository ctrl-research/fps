#!/usr/bin/env bash
#
# Fetch the webrtc-native GDExtension into addons/webrtc/.
#
# This is needed for WebRTC (online) multiplayer in DESKTOP builds. The web export
# has WebRTC built in and does NOT need this. The game runs fine without it — the
# online Host/Join buttons are simply disabled on desktop — so this is best-effort
# and never fails the build.
#
# Pin the version with WEBRTC_VERSION. Releases:
#   https://github.com/godotengine/webrtc-native/releases
#
# Usage: WEBRTC_VERSION=1.2.0 scripts/fetch_webrtc.sh
set -uo pipefail

WEBRTC_VERSION="${WEBRTC_VERSION:-1.2.0}"
DEST="addons/webrtc"
URL="https://github.com/godotengine/webrtc-native/releases/download/${WEBRTC_VERSION}/webrtc-native-${WEBRTC_VERSION}.zip"

echo "Fetching webrtc-native ${WEBRTC_VERSION}"
echo "  from ${URL}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -fsSL -o "$tmp/webrtc.zip" "$URL"; then
  echo "WARNING: could not download webrtc-native ${WEBRTC_VERSION}." >&2
  echo "         Desktop online (WebRTC) play will be unavailable; web is unaffected." >&2
  echo "         Set WEBRTC_VERSION to a valid release tag from" >&2
  echo "         https://github.com/godotengine/webrtc-native/releases" >&2
  exit 0
fi

unzip -q "$tmp/webrtc.zip" -d "$tmp/extracted"
mkdir -p addons

# Release archives have historically shipped either webrtc/ or addons/webrtc/.
if [ -d "$tmp/extracted/addons/webrtc" ]; then
  rm -rf "$DEST"; mv "$tmp/extracted/addons/webrtc" "$DEST"
elif [ -d "$tmp/extracted/webrtc" ]; then
  rm -rf "$DEST"; mv "$tmp/extracted/webrtc" "$DEST"
else
  echo "WARNING: unexpected webrtc-native archive layout; extension not installed." >&2
  echo "         Inspect the archive and adjust scripts/fetch_webrtc.sh." >&2
  exit 0
fi

echo "Installed webrtc-native into ${DEST}/"
