"use strict";

/**
 * WebRTC signaling broker for the FPS game.
 *
 * This server ONLY brokers the WebRTC connection handshake (offers, answers, and
 * ICE candidates) between peers in a room. Once peers are connected, all game
 * traffic flows directly peer-to-peer and never touches this server — so it idles
 * at near-zero cost.
 *
 * It speaks plain ws:// and is meant to run behind a TLS-terminating reverse proxy
 * (e.g. Caddy) that exposes wss:// to browsers. Do NOT expose the raw port to the
 * internet — only the proxy should reach it. See README.md.
 *
 * It holds no accounts, no persistence, and no game data, so the realistic threat
 * is abuse / denial-of-service. The limits below (all env-tunable) bound how much
 * a single client or IP can consume.
 *
 * Protocol (JSON text frames). Host is always peer id 1; clients get ids >= 2.
 *   client -> server:
 *     {type:"join", room:"<CODE>"}      empty/missing room => create a room and host it
 *     {type:"offer"|"answer", id:<dest>, sdp:"..."}
 *     {type:"candidate", id:<dest>, mid:"...", index:N, name:"..."}
 *     {type:"seal"}                     host only: lock the room (no more joins)
 *   server -> client:
 *     {type:"id", id:<your id>, room:"<CODE>", host:<bool>}
 *     {type:"peer_connect", id:<peer>} / {type:"peer_disconnect", id:<peer>}
 *     {type:"offer"|"answer"|"candidate", id:<source peer>, ...payload}   (relayed)
 *     {type:"seal"} / {type:"error", reason:"<code>"}
 */

const http = require("http");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

function intEnv(name, fallback) {
  const value = parseInt(process.env[name] || "", 10);
  return Number.isFinite(value) ? value : fallback;
}

// --- Configuration (env-tunable, with safe defaults) ---
const PORT = intEnv("PORT", 9080);
const MAX_PEERS = intEnv("MAX_PEERS", 10);
// Cap frame size: signaling messages are tiny; SDP is a few KB. (ws default is ~100MB.)
const MAX_MESSAGE_BYTES = intEnv("MAX_MESSAGE_BYTES", 32768);
// Bound resource use per source IP and globally.
const MAX_CONNECTIONS_PER_IP = intEnv("MAX_CONNECTIONS_PER_IP", 20);
const MAX_ROOMS = intEnv("MAX_ROOMS", 1000);
// Per-connection flood guard and idle-without-joining cutoff.
const MAX_MESSAGES_PER_SEC = intEnv("MAX_MESSAGES_PER_SEC", 30);
const JOIN_TIMEOUT_MS = intEnv("JOIN_TIMEOUT_MS", 10000);
const HEARTBEAT_MS = intEnv("HEARTBEAT_MS", 30000);
// CSWSH defense: comma-separated allowed browser Origins. Empty => allow any
// origin (native clients send no Origin and are always allowed).
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "")
  .split(",").map((s) => s.trim()).filter(Boolean);

const HOST_ID = 1;
const ROOM_CODE_LENGTH = 5;
// Unambiguous alphabet (no 0/O/1/I) so codes are easy to share verbally.
const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

// roomCode -> { peers: Map<peerId, ws>, nextId: number, sealed: boolean }
const rooms = new Map();
// ip -> open connection count
const connectionsByIp = new Map();

function log(message) {
  console.log(`[${new Date().toISOString()}] ${message}`);
}

function send(ws, msg) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

function closeWithError(ws, reason) {
  send(ws, { type: "error", reason });
  ws.close();
}

function clientIp(req) {
  // Behind a reverse proxy, the real client IP is in X-Forwarded-For.
  const forwarded = req.headers["x-forwarded-for"];
  if (forwarded) {
    return String(forwarded).split(",")[0].trim();
  }
  return (req.socket && req.socket.remoteAddress) || "unknown";
}

function originAllowed(origin) {
  if (ALLOWED_ORIGINS.length === 0) {
    return true; // unrestricted
  }
  if (!origin) {
    return true; // native (non-browser) clients send no Origin
  }
  return ALLOWED_ORIGINS.includes(origin);
}

function makeRoomCode() {
  let code;
  do {
    const bytes = crypto.randomBytes(ROOM_CODE_LENGTH);
    code = "";
    for (let i = 0; i < ROOM_CODE_LENGTH; i++) {
      code += ROOM_CODE_ALPHABET[bytes[i] % ROOM_CODE_ALPHABET.length];
    }
  } while (rooms.has(code));
  return code;
}

function handleJoin(ws, msg) {
  if (ws.room !== null) {
    return closeWithError(ws, "already_joined");
  }

  const requested = String(msg.room || "").toUpperCase().trim();

  if (requested === "") {
    // Create a fresh room and become its host (peer id 1).
    if (rooms.size >= MAX_ROOMS) {
      return closeWithError(ws, "server_full");
    }
    const code = makeRoomCode();
    const room = { peers: new Map(), nextId: HOST_ID + 1, sealed: false };
    rooms.set(code, room);
    ws.room = code;
    ws.peerId = HOST_ID;
    room.peers.set(HOST_ID, ws);
    clearTimeout(ws.joinTimer);
    send(ws, { type: "id", id: HOST_ID, room: code, host: true });
    log(`room ${code} created by host (${rooms.size} rooms)`);
    return;
  }

  const room = rooms.get(requested);
  if (!room) return closeWithError(ws, "room_not_found");
  if (room.sealed) return closeWithError(ws, "room_sealed");
  if (room.peers.size >= MAX_PEERS) return closeWithError(ws, "room_full");

  const id = room.nextId++;
  ws.room = requested;
  ws.peerId = id;
  clearTimeout(ws.joinTimer);

  // Introduce the newcomer to existing peers (both directions) before adding it,
  // so we don't send a peer_connect for the newcomer to itself.
  for (const [otherId, otherWs] of room.peers) {
    send(ws, { type: "peer_connect", id: otherId });
    send(otherWs, { type: "peer_connect", id });
  }

  room.peers.set(id, ws);
  send(ws, { type: "id", id, room: requested, host: false });
  log(`peer ${id} joined room ${requested} (${room.peers.size} peers)`);
}

// Relay a handshake message to a roommate. Only known fields are forwarded
// (the source id is server-set), so a peer can't smuggle arbitrary data through.
function relay(ws, msg) {
  const room = ws.room ? rooms.get(ws.room) : null;
  if (!room || ws.peerId === null) return;
  const dest = room.peers.get(Number(msg.id));
  if (!dest) return;

  const out = { type: msg.type, id: ws.peerId };
  if (msg.type === "candidate") {
    out.mid = String(msg.mid || "");
    out.index = Number(msg.index) || 0;
    out.name = String(msg.name || "");
  } else {
    out.sdp = String(msg.sdp || "");
  }
  send(dest, out);
}

function handleSeal(ws) {
  const room = ws.room ? rooms.get(ws.room) : null;
  if (!room || ws.peerId !== HOST_ID) return; // only the host may seal
  room.sealed = true;
  for (const [, peerWs] of room.peers) send(peerWs, { type: "seal" });
  log(`room ${ws.room} sealed`);
}

function handleClose(ws) {
  const code = ws.room;
  if (!code) return;
  const room = rooms.get(code);
  if (!room) return;

  room.peers.delete(ws.peerId);

  if (ws.peerId === HOST_ID) {
    // Host left: tear the whole room down.
    for (const [, peerWs] of room.peers) {
      send(peerWs, { type: "peer_disconnect", id: HOST_ID });
      peerWs.close();
    }
    rooms.delete(code);
    log(`room ${code} closed (host left)`);
    return;
  }

  for (const [, peerWs] of room.peers) {
    send(peerWs, { type: "peer_disconnect", id: ws.peerId });
  }
  log(`peer ${ws.peerId} left room ${code} (${room.peers.size} peers)`);
  if (room.peers.size === 0) {
    rooms.delete(code);
  }
}

// Per-connection message rate limit (sliding 1s window). Returns false if over.
function withinRateLimit(ws) {
  const now = Date.now();
  if (now - ws.msgWindowStart >= 1000) {
    ws.msgWindowStart = now;
    ws.msgCount = 0;
  }
  ws.msgCount++;
  return ws.msgCount <= MAX_MESSAGES_PER_SEC;
}

function handleMessage(ws, raw) {
  if (!withinRateLimit(ws)) {
    return closeWithError(ws, "rate_limited");
  }

  let msg;
  try {
    msg = JSON.parse(raw.toString());
  } catch (_e) {
    return closeWithError(ws, "invalid_json");
  }
  if (typeof msg !== "object" || msg === null) {
    return closeWithError(ws, "invalid_message");
  }

  // One bad client must not take down the broker for everyone.
  try {
    switch (msg.type) {
      case "join":
        return handleJoin(ws, msg);
      case "offer":
      case "answer":
      case "candidate":
        return relay(ws, msg);
      case "seal":
        return handleSeal(ws);
      default:
        return closeWithError(ws, "unknown_type");
    }
  } catch (err) {
    log(`handler error: ${err}`);
    closeWithError(ws, "server_error");
  }
}

function onClose(ws) {
  clearTimeout(ws.joinTimer);
  const remaining = (connectionsByIp.get(ws.ip) || 1) - 1;
  if (remaining <= 0) {
    connectionsByIp.delete(ws.ip);
  } else {
    connectionsByIp.set(ws.ip, remaining);
  }
  handleClose(ws);
}

const server = http.createServer((req, res) => {
  // Plain-HTTP health check for uptime monitoring / load balancers.
  if (req.url === "/health" || req.url === "/") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({
  server,
  maxPayload: MAX_MESSAGE_BYTES,
  verifyClient: (info) => originAllowed(info.origin),
});

wss.on("connection", (ws, req) => {
  const ip = clientIp(req);
  const current = connectionsByIp.get(ip) || 0;
  if (current >= MAX_CONNECTIONS_PER_IP) {
    return closeWithError(ws, "too_many_connections");
  }
  connectionsByIp.set(ip, current + 1);

  ws.isAlive = true;
  ws.room = null;
  ws.peerId = null;
  ws.ip = ip;
  ws.msgWindowStart = Date.now();
  ws.msgCount = 0;
  // Drop connections that linger without ever joining a room.
  ws.joinTimer = setTimeout(() => {
    if (ws.room === null) {
      closeWithError(ws, "join_timeout");
    }
  }, JOIN_TIMEOUT_MS);

  ws.on("pong", () => { ws.isAlive = true; });
  ws.on("message", (raw) => handleMessage(ws, raw));
  ws.on("close", () => onClose(ws));
  ws.on("error", () => {}); // close handler performs cleanup
});

// Drop dead connections so rooms don't leak when a peer vanishes ungracefully.
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_MS);
wss.on("close", () => clearInterval(heartbeat));

// Keep the broker alive through unexpected errors (a process manager / Docker
// restart policy is still recommended as a backstop).
process.on("uncaughtException", (err) => log(`uncaughtException: ${err && err.stack ? err.stack : err}`));
process.on("unhandledRejection", (err) => log(`unhandledRejection: ${err}`));

server.listen(PORT, () => {
  log(`signaling server listening on :${PORT}`);
  log(`limits: ${MAX_PEERS} peers/room, ${MAX_ROOMS} rooms, ${MAX_CONNECTIONS_PER_IP} conns/ip, ` +
    `${MAX_MESSAGES_PER_SEC} msgs/s, ${MAX_MESSAGE_BYTES}B/msg, join timeout ${JOIN_TIMEOUT_MS}ms`);
  log(`allowed origins: ${ALLOWED_ORIGINS.length ? ALLOWED_ORIGINS.join(", ") : "(any)"}`);
});
