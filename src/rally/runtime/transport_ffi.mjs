// @ts-check
//
// Rally WebSocket transport layer.
//
// Imports encode/decode from the generated protocol_wire.mjs facade.
// The facade delegates to libero's ETF or JSON wire modules depending
// on the configured protocol. This file handles only the WebSocket
// connection lifecycle, reconnects, RPC callbacks, push handlers,
// SSR flags, and debug logging.

import { Ok, Error as ResultError, CustomType, Empty, NonEmpty, BitArray } from "../../gleam_stdlib/gleam.mjs";
import { encode_request, decode_server_frame } from "./protocol_wire.mjs";
import { MalformedRequest, UnknownFunction, InternalError } from "../../libero/libero/error.mjs";

// ---------- Debug logging ----------

function debugEnabled() {
  if (typeof window === "undefined") return false;
  return window.__RALLY_DEBUG__ === true
      || window.__APP_ENV__ === "dev";
}

function formatRaw(value, depth = 0) {
  if (value === undefined || value === null) return "Nil";
  if (typeof value === "boolean") return value ? "True" : "False";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  if (value instanceof BitArray) return `<<${value.rawBuffer.length} bytes>>`;
  if (value && value.__liberoRawBinary) return `<<${value.rawBuffer.length} bytes>>`;
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    if (typeof value[0] === "string" && /^[a-z_]/.test(value[0])) {
      const tag = pascalCase(value[0]);
      if (value.length === 1) return tag;
      const fields = value.slice(1).map(v => formatRaw(v, depth + 1));
      return `${tag}(${fields.join(", ")})`;
    }
    const items = value.map(v => formatRaw(v, depth + 1));
    return `#(${items.join(", ")})`;
  }
  if (value instanceof Empty) return "[]";
  if (value instanceof NonEmpty) {
    const items = gleamListToArray(value).map(v => formatRaw(v, depth + 1));
    return `[${items.join(", ")}]`;
  }
  if (value instanceof Map) {
    const pairs = [...value.entries()].map(([k, v]) => `${formatRaw(k)}: ${formatRaw(v, depth + 1)}`);
    return `dict.from_list([${pairs.join(", ")}])`;
  }
  if (value instanceof CustomType) {
    const name = value.constructor.name;
    const keys = Object.keys(value);
    if (keys.length === 0) return name;
    const fields = keys.map(k => formatRaw(value[k], depth + 1));
    return `${name}(${fields.join(", ")})`;
  }
  return String(value);
}

function gleamListToArray(list) {
  const out = [];
  let node = list;
  while (node instanceof NonEmpty) {
    out.push(node.head);
    node = node.tail;
  }
  return out;
}

function pascalCase(snake) {
  return snake.split("_").map(s => s.charAt(0).toUpperCase() + s.slice(1)).join("");
}

function recordMessage(direction, label, data, extra) {
  if (typeof window === "undefined") return;
  if (!window.__RALLY_MESSAGES__) window.__RALLY_MESSAGES__ = [];
  const entry = {
    t: performance.now(),
    ts: new Date().toISOString(),
    dir: direction,
    label,
    data,
    formatted: formatRaw(data),
  };
  if (extra) entry.extra = extra;
  window.__RALLY_MESSAGES__.push(entry);
  if (window.__RALLY_MESSAGES__.length > 1000) {
    window.__RALLY_MESSAGES__ = window.__RALLY_MESSAGES__.slice(-500);
  }
}

function logRpc(direction, label, data, extra) {
  if (!debugEnabled()) return;
  recordMessage(direction, label, data, extra);
  const colors = {
    "->": "color: #e8a033; font-weight: bold",
    "<-": "color: #33bbe8; font-weight: bold",
    "<<": "color: #b833e8; font-weight: bold",
  };
  const arrow = direction;
  const style = colors[arrow] || "";
  const parts = [`%c${arrow} ${label}`, style];
  console.groupCollapsed(...parts);
  console.log(formatRaw(data));
  if (extra) {
    for (const [k, v] of Object.entries(extra)) {
      console.log(`${k}:`, v);
    }
  }
  console.groupEnd();
}

if (typeof window !== "undefined") {
  window.__RALLY_FORMAT__ = formatRaw;
}

// ---------- WebSocket ----------
//
// `send` opens the WebSocket lazily on first call and caches the
// connection. The URL is a compile-time constant from Gleam's
// rpc_config module, so it doesn't change across calls. Sends issued
// before the socket's open event are queued and flushed once it opens.
//
// Server→client frames are decoded through Libero's boundary API.
// decode_server_frame returns { kind: "response", requestId, value }
// or { kind: "push", module, value }. Rally never inspects tag bytes
// or slices frame headers — Libero owns that boundary.
//
// Responses are matched by request ID (monotonic counter assigned by
// the client). This allows safe timeout handling without closing the
// WebSocket; late responses for timed-out requests are harmlessly
// dropped since their ID has been removed from the callback Map.
//
// Reconnection is automatic. On unexpected close (network blip, server
// restart, page resume from sleep), the socket reconnects with
// exponential backoff (500ms → 30s, full jitter). Pending requests
// report a connection-lost framework error rather than wait; application
// code retries idempotently or surfaces the error. Push handlers
// remain registered across reconnects, so push frames resume once the
// socket is back. Apps that need to refetch state on reconnect should
// register an `on_connect` listener (see registerOnConnect below).

let ws = null;
let pendingSends = [];    // [{payload, requestId, callback, timer}]
let responseCallbacks = new Map(); // requestId -> {callback, timer}
let nextRequestId = 1;
const REQUEST_TIMEOUT_MS = 30_000;
const requestTimestamps = new Map();

// Push handler registry: module path → callback
const pushHandlers = new Map();

// Connection lifecycle listeners. `on_connect` fires on every socket
// open; first connect AND reconnects; so apps can use one path for
// "load initial state". `on_disconnect` fires when the socket closes
// (the reason string is human-readable and intended for UX).
const onConnectListeners = new Set();
const onDisconnectListeners = new Set();

// Reconnect state. lastUrl is captured on first ensureSocket() so
// auto-reconnect can re-create the socket without the caller passing
// the URL again.
let lastUrl = null;
let reconnectTimer = null;
let reconnectAttempts = 0;
const RECONNECT_BASE_MS = 500;
const RECONNECT_MAX_MS = 30_000;

// Build a framework-level connection error for the global RPC error
// handler. Per-call callbacks only receive handler return values.
function makeConnectionError(message) {
  return new InternalError("", message);
}

function formatFrameworkError(error) {
  if (error instanceof UnknownFunction) return "UnknownFunction(\"" + error.name + "\")";
  if (error instanceof InternalError) return "InternalError(trace: " + error.trace_id + ", message: \"" + error.message + "\")";
  if (error instanceof MalformedRequest) return "MalformedRequest";
  return String(error);
}

let rpcErrorHandler = null;

export function registerRpcErrorHandler(handler) {
  rpcErrorHandler = handler;
}

function invokeRpcErrorHandler(error, context = "RPC framework error") {
  const message = formatFrameworkError(error);
  if (rpcErrorHandler) {
    try {
      rpcErrorHandler(message);
    } catch (e) {
      if (debugEnabled()) console.error("[rally] rpc error handler threw:", e);
    }
    return;
  }
  if (debugEnabled()) console.error("[rally] " + context + ":", message);
}

function toWebSocketPayload(payload) {
  if (payload && payload.rawBuffer instanceof Uint8Array) {
    return payload.rawBuffer;
  }
  return payload;
}

/**
 * Pure detection of auth protocol error strings from the server.
 *
 * The server sends Error("auth:redirect:<url>") when a Required page
 * blocks unauthenticated access, and Error("auth:forbidden") when
 * authorize fails.
 *
 * Unknown auth:* values, non-string errors, and non-Error values
 * return null and fall through to the existing response path.
 *
 * @param {any} value - decoded frame value (may be Ok, ResultError, or other)
 * @returns {{ kind: "redirect", url: string } | { kind: "forbidden" } | null}
 */
export function detectAuthError(value) {
  if (!(value instanceof ResultError)) return null;
  const errValue = value[0];
  if (typeof errValue !== "string") return null;

  if (errValue.startsWith("auth:redirect:")) {
    return { kind: "redirect", url: errValue.slice("auth:redirect:".length) };
  }
  if (errValue === "auth:forbidden") {
    return { kind: "forbidden" };
  }
  return null;
}

/**
 * Handle auth protocol errors from the server with side effects.
 *
 * For page-init (request_id 0), there is no registered callback so
 * this is the only path that catches auth failures.
 *
 * For RPC, pending callbacks are cleaned up without being invoked
 * (callbacks only handle success values). The app is notified via
 * the registered RPC error handler or a console error.
 *
 * @param {{ kind: string, requestId: number, value: any }} frame
 * @returns {boolean} true if the frame was handled as an auth error
 */
function handleAuthError(frame) {
  const detected = detectAuthError(frame.value);
  if (!detected) return false;

  // Clean up pending RPC state so callers don't hang
  const entry = responseCallbacks.get(frame.requestId);
  if (entry) {
    responseCallbacks.delete(frame.requestId);
    if (entry.timer) clearTimeout(entry.timer);
  }
  requestTimestamps.delete(frame.requestId);

  if (detected.kind === "redirect") {
    if (typeof window !== "undefined" && window.location) {
      window.location.href = detected.url;
    }
    return true;
  }

  // forbidden
  const message = "auth:forbidden";
  if (rpcErrorHandler) {
    try {
      rpcErrorHandler(message);
    } catch (e) {
      if (debugEnabled()) console.error("[rally] rpc error handler threw:", e);
    }
  } else if (debugEnabled()) {
    console.error("[rally] Auth error:", message);
  }
  return true;
}

function clearAllPending(reason) {
  const error = makeConnectionError(reason);
  for (const entry of pendingSends) {
    if (entry.timer) clearTimeout(entry.timer);
    if (entry.callback) invokeRpcErrorHandler(error, "RPC request failed");
  }
  for (const [, entry] of responseCallbacks) {
    if (entry.timer) clearTimeout(entry.timer);
    invokeRpcErrorHandler(error, "RPC request failed");
  }
  pendingSends = [];
  responseCallbacks = new Map();
  requestTimestamps.clear();
}

// Compute the next reconnect delay with full jitter: pick a value in
// [cap/2, cap] where cap doubles each attempt. The jitter avoids a
// thundering herd if many clients drop and reconnect together.
function nextReconnectDelay() {
  const cap = Math.min(
    RECONNECT_BASE_MS * Math.pow(2, reconnectAttempts),
    RECONNECT_MAX_MS,
  );
  return cap / 2 + Math.random() * (cap / 2);
}

function scheduleReconnect() {
  if (reconnectTimer !== null) return;
  if (lastUrl === null) return;
  const delay = nextReconnectDelay();
  reconnectAttempts += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    if (ws === null) ensureSocket(lastUrl);
  }, delay);
}

function cancelReconnect() {
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

export function ensureSocket(url) {
  if (ws !== null) {
    return;
  }

  lastUrl = url;
  let sock;
  try {
    sock = new WebSocket(url);
    if (typeof window !== "undefined") window.__RALLY_WS__ = sock;
  } catch (e) {
    clearAllPending("WebSocket constructor failed: " + (e && e.message ? e.message : String(e)));
    scheduleReconnect();
    return;
  }
  ws = sock;
  ws.binaryType = "arraybuffer";

  ws.addEventListener("open", () => {
    if (debugEnabled()) {
      const label = reconnectAttempts > 0 ? "reconnected" : "connected";
      console.log(`%c-- ${label} --`, "color: #33e855; font-weight: bold");
    }
    reconnectAttempts = 0;
    cancelReconnect();
    // Fire onConnect listeners first (triggers page_init which establishes
    // the server-side session), then flush pending RPC calls.
    for (const listener of onConnectListeners) {
      try { listener(); } catch (_) { /* swallow listener exceptions */ }
    }
    // Small delay to let page_init reach the server before RPC calls.
    // Without this, pending sends race with the WS handler setup.
    setTimeout(() => {
      for (const entry of pendingSends) {
        ws.send(entry.payload);
        if (entry.callback) {
          responseCallbacks.set(entry.requestId, { callback: entry.callback, timer: entry.timer });
        }
      }
      pendingSends = [];
    }, 50);
  });

  ws.addEventListener("message", (event) => {
    const result = decode_server_frame(event.data);
    if (result instanceof ResultError) {
      if (debugEnabled()) console.warn("rally: failed to decode server frame", result[0]);
      return;
    }
    const frame = result[0];

    if (frame.kind === "push") {
      logRpc("<<", `push ${frame.module}`, frame.value);
      const handler = pushHandlers.get(frame.module);
      if (handler) handler(frame.value);
      return;
    }

    if (frame.kind === "error") {
      const msg = frame.errors
        ? (Array.isArray(frame.errors)
            ? frame.errors.map(e => (e && e[1]) || "").join("; ")
            : String(frame.errors))
        : "JSON protocol error";
      if (frame.requestId != null) {
        const entry = responseCallbacks.get(frame.requestId);
        if (entry) {
          responseCallbacks.delete(frame.requestId);
          if (entry.timer) clearTimeout(entry.timer);
        }
        requestTimestamps.delete(frame.requestId);
      }
      invokeRpcErrorHandler(makeConnectionError(msg), "JSON protocol error");
      return;
    }

    // Auth error detection: runs for all response frames (page-init and RPC).
    // The server sends Error("auth:redirect:<url>") and Error("auth:forbidden")
    // as wire error responses for auth policy failures. Page-init (request_id 0)
    // has no registered callback, so this must run before the callback lookup.
    if (handleAuthError(frame)) return;

    // Response frame
    const entry = responseCallbacks.get(frame.requestId);
    if (entry) {
      responseCallbacks.delete(frame.requestId);
      if (entry.timer) clearTimeout(entry.timer);
      const sentAt = requestTimestamps.get(frame.requestId);
      if (sentAt !== undefined) {
        requestTimestamps.delete(frame.requestId);
        const ms = (performance.now() - sentAt).toFixed(1);
        logRpc("<-", `rpc #${frame.requestId} (${ms}ms)`, frame.value);
      } else {
        logRpc("<-", `rpc #${frame.requestId}`, frame.value);
      }
      const decoded = frame.value;
      if (decoded instanceof Ok) {
        entry.callback(decoded[0]);
      } else if (decoded instanceof ResultError) {
        const frameworkError = decoded[0];
        invokeRpcErrorHandler(frameworkError, `RPC #${frame.requestId} failed`);
      } else {
        if (debugEnabled()) console.warn("rally: unexpected response shape #" + frame.requestId, decoded);
      }
    }
  });

  ws.addEventListener("close", () => {
    if (!ws) {
      scheduleReconnect();
      return;
    }
    ws = null;
    if (debugEnabled()) {
      console.log("%c-- disconnected --", "color: #e83333; font-weight: bold");
    }
    clearAllPending("WebSocket connection closed");
    for (const listener of onDisconnectListeners) {
      try { listener("connection closed"); } catch (_) { /* swallow */ }
    }
    scheduleReconnect();
  });

  ws.addEventListener("error", () => {
    if (ws) {
      const sock = ws;
      ws = null;
      // Clear pending callbacks immediately so the close handler (which
      // fires asynchronously) doesn't operate on stale state. The close
      // handler will fire scheduleReconnect; we just need clean teardown.
      clearAllPending("WebSocket error");
      for (const listener of onDisconnectListeners) {
        try { listener("connection error"); } catch (_) { /* swallow */ }
      }
      sock.close();
    }
  });
}

/**
 * Register a callback that fires whenever the WebSocket connection
 * opens; both the initial connect and every successful reconnect.
 * Use this to load (or reload) state without a separate code path
 * for the first connection.
 * @param {() => void} callback
 */
export function registerOnConnect(callback) {
  onConnectListeners.add(callback);
}

/**
 * Register a callback that fires when the WebSocket disconnects.
 * The reason is a human-readable string suitable for UX messaging.
 * @param {(reason: string) => void} callback
 */
export function registerOnDisconnect(callback) {
  onDisconnectListeners.add(callback);
}

/**
 * Send a message and queue a callback for the server's response.
 * Responses are matched by request ID. Each request has a 30-second
 * timeout; if no response arrives, the registered RPC error handler
 * receives an InternalError so the UI doesn't hang indefinitely.
 * @param {string} url WebSocket URL (typically from rpc_config)
 * @param {string} module wire envelope string (codegen emits "rpc")
 * @param {any} msg the typed ClientMsg value to encode and send
 * @param {(result: any) => void} callback invoked with the handler return value
 */
export function send(url, module, msg, callback) {
  ensureSocket(url);
  const requestId = nextRequestId++;
  const payload = toWebSocketPayload(encode_request(module, requestId, msg));
  if (debugEnabled()) requestTimestamps.set(requestId, performance.now());
  logRpc("->", `rpc #${requestId}`, msg, { module });

  const timer = setTimeout(() => {
    // Remove from whichever state this request is in.
    const pendingIdx = pendingSends.findIndex(e => e.requestId === requestId);
    if (pendingIdx !== -1) {
      pendingSends.splice(pendingIdx, 1);
    }
    responseCallbacks.delete(requestId);
    requestTimestamps.delete(requestId);
    invokeRpcErrorHandler(makeConnectionError("Request timed out"), `RPC #${requestId} timed out`);
    // No need to close the WebSocket; request IDs prevent FIFO desync.
  }, REQUEST_TIMEOUT_MS);

  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(payload);
    responseCallbacks.set(requestId, { callback, timer });
  } else {
    pendingSends.push({ payload, requestId, callback, timer });
  }
}

/**
 * Send a page init frame with route params. Uses request_id 0 as the
 * init sentinel. The server initializes the page's ServerModel with
 * these params instead of requiring a separate Load message.
 * @param {string} url WebSocket URL
 * @param {string} module page name
 * @param {any} params route params value
 */
export function send_page_init(url, module, params) {
  ensureSocket(url);
  const payload = toWebSocketPayload(encode_request(module, 0, params));
  logRpc("->", `page_init ${module}`, params);
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(payload);
  } else {
    pendingSends.push({ payload, requestId: null, callback: null, timer: null });
  }
}

/**
 * Register a push handler for a specific module. When the server
 * sends a push frame tagged with this module path, the callback is
 * invoked with the decoded value.
 * @param {string} module shared module path
 * @param {(value: any) => void} callback
 */
export function registerPushHandler(module, callback) {
  pushHandlers.set(module, callback);
}

/**
 * Encode a request envelope: `{module_name, request_id, msg}` as ETF binary.
 * Symmetric with the server-side `wire.decode_request`. Returns a raw
 * ArrayBuffer (not a Gleam BitArray) because this is only called
 * internally by `send()`, which passes it directly to `WebSocket.send()`.
 * Compare with `encode_value()` which returns a BitArray for Gleam callers.
 * @param {string} module
 * @param {number} requestId
 * @param {any} msg
 * @returns {ArrayBuffer}
 */
/**
 * Read SSR flags from window.__RALLY_FLAGS__ and clear them.
 * Returns the base64 ETF string or empty string if not present.
 */
export function read_flags() {
  const flags = window.__RALLY_FLAGS__ || "";
  delete window.__RALLY_FLAGS__;
  return flags;
}

export function read_client_context() {
  const ctx = window.__RALLY_CLIENT_CONTEXT__ || "";
  delete window.__RALLY_CLIENT_CONTEXT__;
  return ctx;
}
