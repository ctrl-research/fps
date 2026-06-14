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

Health check: `GET /health` → `200 ok` (also `GET /`).

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
