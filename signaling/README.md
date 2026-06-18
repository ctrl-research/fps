# FPS Signaling Broker

A tiny WebSocket server that brokers the **WebRTC connection handshake** between players.
It relays offers, answers, and ICE candidates within a room — and nothing else. Once two
players are connected, all game traffic flows **directly peer-to-peer** and never touches
this server, so it idles at near-zero cost.

It speaks plain `ws://`. Put a TLS-terminating reverse proxy (Caddy) in front of it so
browsers (served from HTTPS) can reach it over `wss://`.

## Protocol

JSON text frames. The host is always peer id `1`; clients are assigned ids `>= 2`.

| Direction | Message |
|-----------|---------|
| client → server | `{type:"join", room:"<CODE>"}` — empty/missing `room` creates a room and hosts it |
| client → server | `{type:"offer"\|"answer"\|"candidate", id:<dest peer>, ...payload}` |
| client → server | `{type:"seal"}` — host only; locks the room so no one else can join |
| server → client | `{type:"id", id:<your id>, room:"<CODE>", host:<bool>}` |
| server → client | `{type:"peer_connect", id:<peer>}` / `{type:"peer_disconnect", id:<peer>}` |
| server → client | relayed `{type:"offer"\|"answer"\|"candidate", id:<source peer>, ...}` |
| server → client | `{type:"seal"}` / `{type:"error", reason:"<code>"}` |

When relaying offer/answer/candidate, the server rewrites `id` from the destination you
sent to the **source peer id**, so the recipient knows who it came from.

## Configuration

| Env var | Default | Meaning |
|---------|---------|---------|
| `PORT` | `9080` | Listen port (plain ws) |
| `MAX_PEERS` | `10` | Max peers per room |
| `MAX_ROOMS` | `1000` | Max concurrent rooms (caps room-creation spam) |
| `MAX_CONNECTIONS_PER_IP` | `20` | Max simultaneous connections from one source IP |
| `MAX_MESSAGES_PER_SEC` | `30` | Per-connection message rate; exceeding it closes the socket |
| `MAX_MESSAGE_BYTES` | `32768` | Max frame size (signaling is tiny; SDP a few KB) |
| `JOIN_TIMEOUT_MS` | `10000` | Drop a connection that never joins a room within this window |
| `HEARTBEAT_MS` | `30000` | Ping interval for reaping dead connections |
| `ALLOWED_ORIGINS` | _(empty = any)_ | Comma-separated browser `Origin` allowlist, e.g. `https://ctrl-research.github.io`. Native (non-browser) clients send no Origin and are always allowed. |

Health check: `GET /health` → `200 ok` (also `GET /`).

## Security notes

The broker holds **no accounts, no persistence, and no game data** (traffic is P2P), so
the realistic threat is **abuse / denial-of-service**. Mitigations baked in:

- **Frame-size, per-IP connection, room-count, and message-rate limits** (above) bound
  what one client/IP can consume.
- **Join timeout** drops sockets that connect but never join.
- **Relay whitelisting** — only known handshake fields are forwarded and the source peer
  id is server-set, so peers can't spoof identity or smuggle arbitrary data.
- **Origin allowlist** (`ALLOWED_ORIGINS`) blocks casual cross-site browser connections.
- **Handler/exception guards** keep one bad client from crashing the process.

Still **your responsibility at deploy time**:

- **Terminate TLS at a reverse proxy and do _not_ expose the raw `ws://` port** to the
  internet — browsers on HTTPS require `wss://`. Firewall the broker port so only the
  proxy reaches it. (Behind a proxy, set `X-Forwarded-For` so the per-IP cap sees real
  client IPs — Caddy does this by default.)
- Run under a restart policy (Docker `--restart` / systemd `Restart=always`) as a backstop.

### A note on player IP exposure (inherent to P2P)

Because game traffic is true peer-to-peer, players' public IPs are visible to each other
during the WebRTC handshake. To hide them you'd route traffic through a **TURN relay**
(extra bandwidth cost, and it partly defeats the free-P2P benefit). Acceptable for a
casual game, but a conscious trade-off.

## Run it

**Node (>= 18):**
```bash
cd signaling
npm install
PORT=9080 npm start
```

**Docker:**
```bash
cd signaling
docker build -t fps-signaling .
docker run -d --restart unless-stopped -p 9080:9080 --name fps-signaling fps-signaling
```

## TLS with Caddy (recommended)

Caddy gets a certificate automatically and proxies WebSocket upgrades with no extra config.
Point a DNS record (e.g. `signal.example.com`) at your host, then:

```caddyfile
signal.example.com {
    reverse_proxy localhost:9080
}
```

Your game then connects to `wss://signal.example.com`.

## systemd (without Docker)

```ini
# /etc/systemd/system/fps-signaling.service
[Unit]
Description=FPS WebRTC signaling broker
After=network.target

[Service]
WorkingDirectory=/opt/fps/signaling
ExecStart=/usr/bin/node server.js
Environment=PORT=9080
Restart=always
User=fps

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now fps-signaling
```

## Point the game at it

Set the signaling URL in the game (Project Settings → `network/signaling/url`, or the
default baked into `systems/project_settings.gd`) to your `wss://` endpoint, e.g.
`wss://signal.example.com`.

## Quick smoke test

```bash
npm i -g wscat
# terminal 1 — host: join with no room, note the returned room code
wscat -c ws://localhost:9080
> {"type":"join"}
< {"type":"id","id":1,"room":"AB3KD","host":true}
# terminal 2 — client: join that room; both sides should see peer_connect
wscat -c ws://localhost:9080
> {"type":"join","room":"AB3KD"}
```
