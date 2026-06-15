# Online Multiplayer (WebRTC P2P)

The game supports two transports:

| Mode | How | Use |
|------|-----|-----|
| **LAN / direct** | Host Game / Join by IP | Same network; uses WebSocket; no server needed |
| **Online (P2P)** | Host Online / Join Online (room code) | Over the internet; uses WebRTC; needs a signaling broker |

Online play uses **WebRTC**: actual game traffic flows **peer-to-peer**, so no server
relays gameplay. A tiny **signaling broker** is used only to set up connections (it brokers
the offer/answer/ICE handshake), then steps aside.

## 1. Deploy the signaling broker

See [`signaling/README.md`](../signaling/README.md). In short: run `signaling/server.js`
(Node or Docker) behind a TLS reverse proxy (Caddy) so browsers can reach it over `wss://`.

## 2. Point the game at your broker

Set the signaling URL — Project Settings → `network/signaling/url` (default
`ws://localhost:9080`). For a deployed broker use your `wss://` endpoint, e.g.
`wss://signal.example.com`. ICE servers live in `network/signaling/ice_servers`
(defaults to free Google STUN).

These are read in `systems/project_settings.gd` (`get_signaling_url()`, `get_ice_servers()`).

## 3. WebRTC support per platform

- **Web export:** WebRTC is built in — nothing to do.
- **Desktop (Windows) export & editor:** needs the `webrtc-native` GDExtension. Run
  `scripts/fetch_webrtc.sh` (CI runs it automatically before the Windows export; run it
  locally too if you want online play from the editor/desktop). Without it the game still
  runs — the online Host/Join buttons are just disabled.

## 4. How players connect

- **Host Online** → the broker creates a room and shows a **room code** (and, on web, a
  shareable URL like `https://<your-pages-url>/#room=ABCDE`).
- **Join Online** → enter the room code, or on web just open the shared URL — it
  auto-joins via the `#room=` fragment (see `_try_auto_join_from_url` in `lobby.gd`).
- The host is peer id 1; the room is **sealed** when the host starts the round.

## NAT / TURN

STUN (default) covers most home networks. Players behind strict/symmetric NAT may fail to
connect P2P; add a **TURN** server to `network/signaling/ice_servers` (with credentials) if
that happens. TURN relays game traffic, so it does consume bandwidth — only add it if needed.

## ⚠️ Status

The WebRTC client path follows Godot's official `webrtc_signaling` demo but has **not yet
been validated end-to-end** against a live broker (it was written without a local Godot /
deployed broker available). The signaling broker itself is unit-tested. Expect to shake out
issues on the first real two-client test — see the PR notes.
