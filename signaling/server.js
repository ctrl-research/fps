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
 * (e.g. Caddy) that exposes wss:// to browsers. See README.md.
 *
 * Protocol (JSON text frames). Host is always peer id 1; clients get ids >= 2.
 *   client -> server:
 *     {type:"join", room:"<CODE>"}      empty/missing room => create a room and host it
 *     {type:"offer"|"answer"|"candidate", id:<dest peer>, ...payload}
 *     {type:"seal"}                     host only: lock the room (no more joins)
 *   server -> client:
 *     {type:"id", id:<your id>, room:"<CODE>", host:<bool>}
 *     {type:"peer_connect", id:<peer>}      a peer you should set up a connection with
 *     {type:"peer_disconnect", id:<peer>}
 *     {type:"offer"|"answer"|"candidate", id:<source peer>, ...payload}   (relayed)
 *     {type:"seal"}
 *     {type:"error", reason:"<code>"}
 */

const http = require("http");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "9080", 10);
const MAX_PEERS = parseInt(process.env.MAX_PEERS || "10", 10);
const HOST_ID = 1;
const ROOM_CODE_LENGTH = 5;
// Unambiguous alphabet (no 0/O/1/I) so codes are easy to share verbally.
const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const HEARTBEAT_MS = 30000;

// roomCode -> { peers: Map<peerId, ws>, nextId: number, sealed: boolean }
const rooms = new Map();

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
    const code = makeRoomCode();
    const room = { peers: new Map(), nextId: HOST_ID + 1, sealed: false };
    rooms.set(code, room);
    ws.room = code;
    ws.peerId = HOST_ID;
    room.peers.set(HOST_ID, ws);
    send(ws, { type: "id", id: HOST_ID, room: code, host: true });
    log(`room ${code} created by host`);
    return;
  }

  const room = rooms.get(requested);
  if (!room) return closeWithError(ws, "room_not_found");
  if (room.sealed) return closeWithError(ws, "room_sealed");
  if (room.peers.size >= MAX_PEERS) return closeWithError(ws, "room_full");

  const id = room.nextId++;
  ws.room = requested;
  ws.peerId = id;

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

function relay(ws, msg) {
  const room = ws.room ? rooms.get(ws.room) : null;
  if (!room || ws.peerId === null) return;
  const dest = room.peers.get(Number(msg.id));
  if (!dest) return;
  // Rewrite the id to the sender so the recipient knows the source peer.
  send(dest, Object.assign({}, msg, { id: ws.peerId }));
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

function handleMessage(ws, raw) {
  let msg;
  try {
    msg = JSON.parse(raw.toString());
  } catch (_e) {
    return closeWithError(ws, "invalid_json");
  }
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

const wss = new WebSocketServer({ server });

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.room = null;
  ws.peerId = null;
  ws.on("pong", () => { ws.isAlive = true; });
  ws.on("message", (raw) => handleMessage(ws, raw));
  ws.on("close", () => handleClose(ws));
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

server.listen(PORT, () => {
  log(`signaling server listening on :${PORT} (max ${MAX_PEERS} peers/room)`);
});
