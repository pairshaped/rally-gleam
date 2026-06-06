//// Page-local load RPC glue generation.
////
//// This module targets the unified-source chase app shape: page-local wire
//// modules own `ServerMsg` and `LoadResult`, while generated glue owns the
//// repetitive request/result envelopes and browser transport callbacks.

import glance
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import libero/field_type
import libero/glance_type_resolver.{type TypeResolver, RejectUnsupported}
import simplifile

pub type GeneratedFile {
  GeneratedFile(path: String, content: String)
}

pub type LoadArg {
  LoadArg(label: String, type_ref: String)
}

pub type PageNavigation {
  PageNavigation(
    source_module: String,
    message_module: String,
    message_constructor: String,
    args: List(LoadArg),
  )
}

pub type LoadRpc {
  LoadRpc(
    /// Stable snake_case name used in generated function names.
    name: String,
    /// The route/page module receiving the request frame.
    module_path: String,
    /// Page-local wire module that defines ServerMsg and LoadResult.
    wire_module: String,
    /// False when the contract lives in the page module, because importing the
    /// page from client transport would create a cycle.
    import_on_client: Bool,
    /// ServerMsg constructor used to request the page load.
    request_constructor: String,
    /// LoadResult constructor used to wrap the loaded page data.
    load_result_constructor: String,
    /// Route modules whose page message type can receive this load result.
    route_modules: List(String),
    /// Page message constructors that navigate to this load route.
    navigation_sources: List(PageNavigation),
    /// Whether this load's Proute mount update dispatcher needs PageContext.
    update_uses_page_context: Bool,
    args: List(LoadArg),
    save_result_type: Option(String),
  )
}

pub type PushContract {
  PushContract(module_path: String, type_name: String)
}

pub type LoadContext {
  LoadContext(module_path: String, type_name: String)
}

type SourceModule {
  SourceModule(
    source_module: String,
    module_path: String,
    wire_module: String,
    import_on_client: Bool,
    ast: glance.Module,
    resolver: TypeResolver,
  )
}

type TargetedImportUse {
  TargetedImportUse(module_path: String, target: String, type_name: String)
}

pub fn discover(src_root src_root: String) -> Result(List(LoadRpc), String) {
  use files <- result.try(walk_directory(path: src_root))
  use modules <- result.try(
    files
    |> list.try_map(fn(path) { source_module_from_file(src_root, path) }),
  )
  use loads <- result.try(
    modules
    |> list.try_fold([], fn(loads, info) {
      use discovered <- result.try(discover_source_module(info, modules))
      Ok(list.append(loads, discovered))
    }),
  )
  loads
  |> list.map(fn(load) {
    let route_modules = load_route_modules(load, modules)
    LoadRpc(
      ..load,
      route_modules:,
      navigation_sources: navigation_sources(load, modules),
      update_uses_page_context: mount_update_uses_page_context(load, modules),
    )
  })
  |> Ok
}

pub fn generate(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
  load_context load_context: Option(LoadContext),
) -> List(GeneratedFile) {
  [
    GeneratedFile(
      "src/generated/rally/client_protocol.gleam",
      client_protocol(loads:, push_contract:),
    ),
    GeneratedFile(
      "src/generated/rally/server_protocol.gleam",
      server_protocol(loads:, push_contract:),
    ),
    GeneratedFile(
      "src/generated/rally/client_transport.gleam",
      client_transport(loads:),
    ),
    GeneratedFile(
      "src/generated/rally/client_transport_ffi.mjs",
      client_transport_ffi(),
    ),
    GeneratedFile("src/generated/rally/server.gleam", page_server(loads:)),
    GeneratedFile(
      "src/generated/rally/server_ws.gleam",
      server_ws(loads:, push_contract:, load_context:),
    ),
    GeneratedFile(
      "src/generated/rally/server_ssr.gleam",
      server_ssr(loads:, load_context:),
    ),
    GeneratedFile("src/generated/rally/hydration.gleam", hydration(loads:)),
    GeneratedFile("src/generated/rally/theme.gleam", theme_module()),
    GeneratedFile("src/generated/rally/browser.gleam", browser_module()),
    GeneratedFile("src/generated/rally/browser_ffi.mjs", browser_ffi()),
    GeneratedFile("src/generated/rally/browser_mount.gleam", browser_mount()),
    GeneratedFile(
      "src/generated/rally/browser_app.gleam",
      browser_app(loads:, push_contract:),
    ),
    GeneratedFile("src/generated/rally/result.gleam", result_module()),
  ]
}

pub fn libero_type_seeds(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
) -> List(#(String, String)) {
  let load_seeds =
    loads
    |> list.flat_map(fn(load) {
      let save_seeds = case load.save_result_type {
        Some(type_name) -> [#(load.wire_module, type_name)]
        None -> []
      }
      [
        #(load.wire_module, "ServerMsg"),
        #(load.wire_module, "LoadResult"),
        ..save_seeds
      ]
    })

  case push_contract {
    Some(PushContract(module_path:, type_name:)) -> [
      #(module_path, type_name),
      ..load_seeds
    ]
    None -> load_seeds
  }
  |> list.unique
}

pub fn result_module() -> String {
  "import gleam/option.{type Option}

pub type ApiLoadError {
  ApiLoadError(message: String)
}

pub type ApiSaveError {
  ApiSaveError(field: Option(String), message: String)
}
"
}

pub fn theme_module() -> String {
  "@target(erlang)
import gleam/http/request.{type Request}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/result

pub const dark_mode_cookie = \"__rally_dark_mode\"

@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
pub fn document_attribute(req: Request(body)) -> String {
  \"data-theme=\\\"\" <> document_theme(req) <> \"\\\"\"
}

@target(erlang)
pub fn document_theme(req: Request(body)) -> String {
  case request_dark_mode(req) {
    True -> \"dark\"
    False -> \"light\"
  }
}

@target(erlang)
pub fn request_dark_mode(req: Request(body)) -> Bool {
  request.get_cookies(req)
  |> list.find_map(fn(cookie) {
    case cookie.0, cookie.1 {
      name, \"1\" if name == dark_mode_cookie -> Ok(True)
      name, \"0\" if name == dark_mode_cookie -> Ok(False)
      _, _ -> Error(Nil)
    }
  })
  |> result.unwrap(False)
}
"
}

pub fn browser_module() -> String {
  "@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"path\")
pub fn path() -> String {
  \"/\"
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"websocket_url\")
pub fn websocket_url() -> String {
  \"ws://localhost:8080/ws\"
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"boot_int\")
pub fn boot_int(_name: String, _fallback: Int) -> Int {
  0
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"boot_string\")
pub fn boot_string(_name: String) -> String {
  \"\"
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"boot_bool\")
pub fn boot_bool(_name: String) -> Bool {
  False
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"take_boot_string\")
pub fn take_boot_string(_name: String) -> String {
  \"\"
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"query_string\")
pub fn query_string() -> String {
  \"\"
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"push_path\")
pub fn push_path(_path: String) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"listen_popstate\")
pub fn listen_popstate(_dispatch: fn(String) -> Nil) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"listen_spa_navigation\")
pub fn listen_spa_navigation(_dispatch: fn(String) -> Nil) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"device_dark_mode\")
pub fn device_dark_mode() -> Bool {
  False
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"apply_dark_mode\")
pub fn apply_dark_mode(_dark_mode: Bool) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./browser_ffi.mjs\", \"persist_dark_mode\")
pub fn persist_dark_mode(_dark_mode: Bool) -> Nil {
  Nil
}
"
}

pub fn browser_ffi() -> String {
  "export function path() {
  return globalThis.location?.pathname || \"/\";
}

export function websocket_url() {
  const location = globalThis.location;
  if (!location) return \"ws://localhost:8080/ws\";
  const protocol = location.protocol === \"https:\" ? \"wss:\" : \"ws:\";
  return `${protocol}//${location.host}/ws`;
}

function bootData() {
  return globalThis.document?.querySelector?.(\"#app\")?.dataset ?? {};
}

export function boot_int(name, fallback) {
  const value = Number.parseInt(bootData()[name] ?? String(fallback), 10);
  return Number.isFinite(value) ? value : fallback;
}

export function boot_string(name) {
  return bootData()[name] ?? \"\";
}

export function boot_bool(name) {
  return bootData()[name] === \"1\";
}

export function take_boot_string(name) {
  const data = bootData();
  const value = data[name] ?? \"\";
  delete data[name];
  return value;
}

export function query_string() {
  const search = globalThis.location?.search ?? \"\";
  const params = new URLSearchParams(search);
  return Array.from(params.entries())
    .map(([key, value]) => `${key}=${value}`)
    .join(\"&\");
}

export function push_path(path) {
  const history = globalThis.history;
  const location = globalThis.location;
  if (!history || !location || location.pathname === path) return;
  history.pushState(null, \"\", path);
}

export function listen_popstate(dispatch) {
  globalThis.addEventListener?.(\"popstate\", () => {
    dispatch(path());
  });
}

export function listen_spa_navigation(dispatch) {
  globalThis.document?.addEventListener?.(\"click\", event => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const link = event.target?.closest?.(\"a[data-rally-spa-nav]\");
    if (!link) return;

    const location = globalThis.location;
    if (!location) return;

    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin) return;

    const destination = url.pathname + url.search;
    if (destination === location.pathname + location.search) {
      event.preventDefault();
      return;
    }

    event.preventDefault();
    dispatch(destination);
  });
}

const darkModeCookie = \"__rally_dark_mode\";

export function device_dark_mode() {
  const raw = getCookie(darkModeCookie);
  if (raw === \"1\") return true;
  if (raw === \"0\") return false;

  return typeof globalThis.matchMedia === \"function\"
    ? globalThis.matchMedia(\"(prefers-color-scheme: dark)\").matches
    : false;
}

export function apply_dark_mode(darkMode) {
  const document = globalThis.document;
  if (!document?.documentElement) return;
  document.documentElement.dataset.theme = darkMode ? \"dark\" : \"light\";
}

export function persist_dark_mode(darkMode) {
  setCookie(darkModeCookie, darkMode ? \"1\" : \"0\", 365);
}

function getCookie(name) {
  const document = globalThis.document;
  if (!document?.cookie) return null;

  const prefix = name + \"=\";
  const pair = document.cookie
    .split(\"; \")
    .find(cookie => cookie.startsWith(prefix));

  return pair ? decodeURIComponent(pair.slice(prefix.length)) : null;
}

function setCookie(name, value, days) {
  const document = globalThis.document;
  if (!document) return;
  const expires = days
    ? \"; expires=\" + new Date(Date.now() + days * 864e5).toUTCString()
    : \"\";
  document.cookie = name + \"=\" + value + \"; Path=/; SameSite=Lax\" + expires;
}
"
}

pub fn browser_mount() -> String {
  "@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
import generated/rally/browser
@target(javascript)
import generated/rally/client_transport
@target(javascript)
import gleam/list
@target(javascript)
import gleam/string
@target(javascript)
import lustre/effect.{type Effect}

@target(javascript)
pub fn device_dark_mode() -> Bool {
  browser.device_dark_mode()
}

@target(javascript)
fn apply_dark_mode(dark_mode: Bool) -> Effect(msg) {
  effect.from(fn(_dispatch) { browser.apply_dark_mode(dark_mode) })
}

@target(javascript)
fn persist_dark_mode(dark_mode: Bool) -> Effect(msg) {
  effect.from(fn(_dispatch) { browser.persist_dark_mode(dark_mode) })
}

@target(javascript)
pub fn dark_mode_changed_effects(dark_mode dark_mode: Bool) -> Effect(msg) {
  effect.batch([
    persist_dark_mode(dark_mode),
    apply_dark_mode(dark_mode),
  ])
}

@target(javascript)
pub fn startup_effects(
  dark_mode dark_mode: Bool,
  on_frame on_frame: fn(BitArray) -> msg,
  on_shell_navigation on_shell_navigation: fn(String) -> msg,
  on_browser_navigation on_browser_navigation: fn(String) -> msg,
) -> Effect(msg) {
  effect.batch([
    apply_dark_mode(dark_mode),
    client_transport.connect(url: browser.websocket_url(), on_frame: on_frame),
    listen_for_shell_navigation(on_shell_navigation),
    listen_for_browser_navigation(on_browser_navigation),
  ])
}

@target(javascript)
pub fn push_path(path: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { browser.push_path(path) })
}

@target(javascript)
fn listen_for_browser_navigation(to_message: fn(String) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    browser.listen_popstate(fn(path) { dispatch(to_message(path)) })
  })
}

@target(javascript)
fn listen_for_shell_navigation(to_message: fn(String) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    browser.listen_spa_navigation(fn(path) { dispatch(to_message(path)) })
  })
}

@target(javascript)
pub fn query_pairs() -> List(#(String, String)) {
  browser.query_string()
  |> string.split(\"&\")
  |> list.filter_map(fn(pair) {
    case string.split(pair, \"=\") {
      [key, value] -> Ok(#(key, value))
      _ -> Error(Nil)
    }
  })
}
"
}

pub fn client_transport_ffi() -> String {
  "let socket = null;
let socketUrl = null;
let pending = [];
let pendingResults = new Map();
let listeners = new Set();
let reconnectTimer = null;
let reconnectAttempts = 0;
let requestId = 0;
let currentTopicFrame = null;
let sentTopicFrame = null;

import { BitArray, Ok } from \"../../gleam.mjs\";
import { decode_result_envelope } from \"./client_protocol.mjs\";

export function next_request_id() {
  requestId += 1;
  return requestId;
}

export function connect(url, onFrame) {
  socketUrl = url;
  listeners.add(onFrame);
  ensure_socket();
  return undefined;
}

export function send_frame(frame) {
  const bytes = bytes_from_bit_array(frame);

  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(bytes);
    return undefined;
  }

  pending.push(bytes);
  ensure_socket();

  globalThis.dispatchEvent(
    new CustomEvent(\"rally:to-server\", {
      detail: { bytes, frame },
    }),
  );
  return undefined;
}

export function send_topic_frame(topics) {
  const names = Array.from(topics);
  const text = names.length === 0 ? \"unsub\" : \"sub:\" + names.join(\",\");
  currentTopicFrame = text;

  if (socket && socket.readyState === WebSocket.OPEN) {
    if (text === sentTopicFrame) return undefined;
    socket.send(text);
    sentTopicFrame = text;
    return undefined;
  }

  pending = pending.filter(frame => !is_topic_frame(frame));
  pending.push(text);
  ensure_socket();
  return undefined;
}

export function send_load_frame(requestId, frame, onResult, dispatch) {
  pendingResults.set(requestId, { onResult, dispatch });
  send_frame(frame);
  return undefined;
}

export function send_save_frame(requestId, frame, onResult, dispatch) {
  pendingResults.set(requestId, { onResult, dispatch });
  send_frame(frame);
  return undefined;
}

function ensure_socket() {
  if (!socketUrl || socket) return;

  try {
    socket = new WebSocket(socketUrl);
  } catch (_) {
    socket = null;
    schedule_reconnect();
    return;
  }

  globalThis.__rallySocket = socket;
  socket.binaryType = \"arraybuffer\";

  socket.addEventListener(\"open\", () => {
    reconnectAttempts = 0;
    sentTopicFrame = null;
    const queued = pending;
    pending = [];
    for (const frame of queued) {
      socket.send(frame);
      if (is_topic_frame(frame)) sentTopicFrame = frame;
    }
    if (currentTopicFrame && currentTopicFrame !== sentTopicFrame) {
      socket.send(currentTopicFrame);
      sentTopicFrame = currentTopicFrame;
    }
  });

  socket.addEventListener(\"message\", event => {
    const bytes = event.data instanceof ArrayBuffer
      ? new Uint8Array(event.data)
      : event.data instanceof Uint8Array
      ? event.data
      : null;
    if (!bytes) return;

    const frame = new BitArray(bytes);
    if (dispatch_result_frame(frame)) return;

    for (const listener of listeners) {
      try { listener(frame); } catch (_) {}
    }
  });

  socket.addEventListener(\"close\", () => {
    socket = null;
    sentTopicFrame = null;
    schedule_reconnect();
  });

  socket.addEventListener(\"error\", () => {
    const current = socket;
    socket = null;
    sentTopicFrame = null;
    if (current) current.close();
    schedule_reconnect();
  });
}

function is_topic_frame(frame) {
  return typeof frame === \"string\" && (frame === \"unsub\" || frame.startsWith(\"sub:\"));
}

function dispatch_result_frame(frame) {
  if (frame.byteAt(0) !== 2) return false;

  const decoded = decode_result_envelope(frame);
  if (!(decoded instanceof Ok)) return true;

  const [requestId, result] = decoded[0];
  const pending = pendingResults.get(requestId);
  if (!pending) return true;

  pendingResults.delete(requestId);
  pending.dispatch(pending.onResult(result));
  return true;
}

function schedule_reconnect() {
  if (reconnectTimer || !socketUrl) return;
  const cap = Math.min(500 * Math.pow(2, reconnectAttempts), 30_000);
  reconnectAttempts += 1;
  const delay = cap / 2 + Math.random() * (cap / 2);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    ensure_socket();
  }, delay);
}

function bytes_from_bit_array(frame) {
  if (frame?.rawBuffer instanceof Uint8Array) return frame.rawBuffer;
  if (frame?.buffer instanceof Uint8Array) return frame.buffer;
  if (frame instanceof Uint8Array) return frame;
  if (frame instanceof ArrayBuffer) return new Uint8Array(frame);
  throw new Error(\"Expected a Gleam BitArray frame\");
}
"
}

pub fn browser_app(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
) -> String {
  let mounts = load_mounts(loads)

  "@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
import generated/rally/browser
@target(javascript)
import generated/rally/browser_mount
@target(javascript)
import generated/rally/client_transport
@target(javascript)
import generated/rally/hydration
@target(javascript)
import generated/rally/result.{type ApiLoadError, ApiLoadError}
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import page_context.{type PageContext}
@target(javascript)
import lustre
@target(javascript)
import lustre/effect.{type Effect}
@target(javascript)
import lustre/element.{type Element}
" <> browser_app_int_import(loads) <> browser_app_list_import(push_contract) <> browser_app_client_protocol_import(
    push_contract,
  ) <> push_import(push_contract, "@target(javascript)") <> browser_app_mount_imports(
    mounts,
  ) <> browser_app_page_imports(loads) <> wire_imports(
    loads,
    "@target(javascript)",
    client_only: False,
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      browser_app_mount_load_route_type(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      browser_app_mount_load_route_function(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      browser_app_mount_navigation_functions(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      browser_app_mount_topic_functions(
        mount,
        mount_loads(loads, mount),
        push_contract:,
      )
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      browser_app_mount_initial_page(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) { browser_app_mount_lifecycle(mount) }),
    "\n",
  ) <> "

@target(javascript)
pub fn start(
  init init: fn(Nil) -> #(model, Effect(msg)),
  update update: fn(model, msg) -> #(model, Effect(msg)),
  view view: fn(model) -> Element(msg),
) -> Nil {
  let app = lustre.application(init, update, view)
  let _started = lustre.start(app, \"#app\", Nil)
  Nil
}

@target(javascript)
pub fn startup_effects(
  page_effect page_effect: Effect(page_msg),
  dark_mode dark_mode: Bool,
  on_page on_page: fn(page_msg) -> msg,
  on_frame on_frame: fn(BitArray) -> msg,
  on_shell_navigation on_shell_navigation: fn(String) -> msg,
  on_browser_navigation on_browser_navigation: fn(String) -> msg,
) -> Effect(msg) {
  effect.batch([
    effect.map(page_effect, on_page),
    browser_mount.startup_effects(
      dark_mode: dark_mode,
      on_frame: on_frame,
      on_shell_navigation: on_shell_navigation,
      on_browser_navigation: on_browser_navigation,
    ),
  ])
}

" <> browser_app_sync_topics(push_contract) <> "

@target(javascript)
pub fn initial_page(
  hydration hydration: Result(result, Nil),
  load_hydrated load_hydrated: fn(result) -> page,
  load_client load_client: fn() -> #(page, Effect(page_msg)),
) -> #(page, Effect(page_msg)) {
  case hydration {
    Ok(result) -> #(load_hydrated(result), effect.none())
    Error(Nil) -> load_client()
  }
}

@target(javascript)
pub fn map_page_effect(
  page_update page_update: #(page, Effect(page_msg)),
  on_page on_page: fn(page_msg) -> msg,
) -> #(page, Effect(msg)) {
  let #(page, page_effect) = page_update
  #(page, effect.map(page_effect, on_page))
}

" <> browser_app_server_frame_effect(push_contract) <> "

@target(javascript)
pub fn navigation_effects(
  path path: String,
  push_history push_history: Bool,
  page_effect page_effect: Effect(page_msg),
  on_page on_page: fn(page_msg) -> msg,
) -> Effect(msg) {
  let history_effect = case push_history {
    True -> browser_mount.push_path(path)
    False -> effect.none()
  }

  effect.batch([history_effect, effect.map(page_effect, on_page)])
}

@target(javascript)
fn initial_loaded_page(
  page page: page,
  page_context page_context: context,
  hydration hydration: Result(result, Nil),
  to_message to_message: fn(result) -> message,
  load_client load_client: fn() -> Effect(message),
  update_page update_page: fn(context, page, message) -> #(page, Effect(message)),
) -> #(page, Effect(message)) {
  case hydration {
    Ok(result) -> {
      let #(page, _) = update_page(page_context, page, to_message(result))
      #(page, effect.none())
    }
    Error(Nil) -> #(page, load_client())
  }
}

@target(javascript)
fn api_load_error(errors: List(ApiLoadError)) -> String {
  case errors {
    [ApiLoadError(message: message), ..] -> message
    [] -> \"Could not load page.\"
  }
}
"
}

fn browser_app_mount_imports(mounts: List(String)) -> String {
  mounts
  |> list.map(fn(mount) { "@target(javascript)
import generated/proute/" <> mount <> "/page_input as " <> mount_alias(
      mount,
      "page_input",
    ) <> "
@target(javascript)
import generated/proute/" <> mount <> "/pages as " <> mount_alias(
      mount,
      "pages",
    ) <> "
@target(javascript)
import generated/proute/" <> mount <> "/routes as " <> mount_alias(
      mount,
      "routes",
    ) })
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn browser_app_mount_lifecycle(mount: String) -> String {
  let prefix = mount_type_prefix(mount)
  let page_input = mount_alias(mount, "page_input")
  let pages = mount_alias(mount, "pages")
  let routes = mount_alias(mount, "routes")
  let model = prefix <> "MountModel"
  let msg = prefix <> "MountMsg"
  let config = prefix <> "MountConfig"
  let page_msg = prefix <> "PageMsg"
  let server_frame = prefix <> "ServerFrame"
  let dark_mode_changed = prefix <> "DarkModeChanged"
  let shell_navigate = prefix <> "ShellNavigate"
  let browser_path_changed = prefix <> "BrowserPathChanged"

  "@target(javascript)
pub type " <> model <> "(shared_state) {
  " <> model <> "(page: " <> pages <> ".Page, shared_state: shared_state)
}

@target(javascript)
pub type " <> msg <> " {
  " <> page_msg <> "(" <> pages <> ".Message)
  " <> server_frame <> "(BitArray)
  " <> dark_mode_changed <> "(Bool)
  " <> shell_navigate <> "(String)
  " <> browser_path_changed <> "(String)
}

@target(javascript)
pub type " <> config <> "(shared_state) {
  " <> config <> "(
    page_context: fn(shared_state) -> PageContext,
    shared_state: fn(String, Bool) -> shared_state,
    set_active_path: fn(shared_state, String) -> shared_state,
    set_dark_mode: fn(shared_state, Bool) -> shared_state,
    update_page: fn(PageContext, " <> pages <> ".Page, " <> pages <> ".Message) ->
      #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)),
    view: fn(
      " <> model <> "(shared_state),
      fn(" <> pages <> ".Message) -> " <> msg <> ",
      fn(Bool) -> " <> msg <> ",
      fn(String) -> " <> msg <> ",
    ) -> Element(" <> msg <> "),
  )
}

@target(javascript)
pub fn start_" <> mount <> "_mount(config config: " <> config <> "(shared_state)) -> Nil {
  start(
    init: fn(_flags) { " <> mount <> "_mount_init(config) },
    update: fn(model, msg) { " <> mount <> "_mount_update(config, model, msg) },
    view: fn(model) {
      config.view(model, " <> page_msg <> ", " <> dark_mode_changed <> ", " <> shell_navigate <> ")
    },
  )
}

@target(javascript)
fn " <> mount <> "_mount_init(
  config config: " <> config <> "(shared_state),
) -> #(" <> model <> "(shared_state), Effect(" <> msg <> ")) {
  let route = " <> routes <> ".parse_path(browser.path())
  let current_path = " <> routes <> ".route_to_path(route)
  let dark_mode = browser_mount.device_dark_mode()
  let query_params = " <> page_input <> ".QueryParams(values: browser_mount.query_pairs())
  let shared_state = config.shared_state(current_path, dark_mode)
  let page_context = config.page_context(shared_state)
  let #(page, page_effect) =
    " <> mount <> "_initial_page(
      page_context:,
      query_params: query_params,
      route:,
      update_page: config.update_page,
    )

  #(
    " <> model <> "(page: page, shared_state:),
    effect.batch([
      startup_effects(
        page_effect: page_effect,
        dark_mode: dark_mode,
        on_page: " <> page_msg <> ",
        on_frame: " <> server_frame <> ",
        on_shell_navigation: " <> shell_navigate <> ",
        on_browser_navigation: " <> browser_path_changed <> ",
      ),
      sync_topics(" <> mount <> "_page_topics(page)),
    ]),
  )
}

@target(javascript)
fn " <> mount <> "_mount_update(
  config config: " <> config <> "(shared_state),
  model model: " <> model <> "(shared_state),
  msg msg: " <> msg <> ",
) -> #(" <> model <> "(shared_state), Effect(" <> msg <> ")) {
  case msg {
    " <> page_msg <> "(inner) -> {
      case " <> mount <> "_message_path(inner) {
        Some(path) -> " <> mount <> "_mount_navigate(
          config: config,
          model: model,
          path: path,
          push_history: True,
        )
        None -> {
          let page_context = config.page_context(model.shared_state)
          let #(page, page_effect) =
            map_page_effect(
              config.update_page(page_context, model.page, inner),
              " <> page_msg <> ",
            )
          #(
            " <> model <> "(..model, page: page),
            effect.batch([
              page_effect,
              sync_topics(" <> mount <> "_page_topics(page)),
            ]),
          )
        }
      }
    }
    " <> server_frame <> "(bytes) -> {
      let #(page, page_effect) =
        server_frame_effect(
          page: model.page,
          bytes: bytes,
          apply_push: " <> mount <> "_apply_push,
          on_page: " <> page_msg <> ",
        )
      #(
        " <> model <> "(..model, page: page),
        effect.batch([
          page_effect,
          sync_topics(" <> mount <> "_page_topics(page)),
        ]),
      )
    }
    " <> dark_mode_changed <> "(dark_mode) -> {
      let shared_state = config.set_dark_mode(model.shared_state, dark_mode)
      #(
        " <> model <> "(..model, shared_state:),
        browser_mount.dark_mode_changed_effects(dark_mode),
      )
    }
    " <> shell_navigate <> "(path) -> {
      " <> mount <> "_mount_navigate(
        config: config,
        model: model,
        path: path,
        push_history: True,
      )
    }
    " <> browser_path_changed <> "(path) -> {
      " <> mount <> "_mount_navigate(
        config: config,
        model: model,
        path: path,
        push_history: False,
      )
    }
  }
}

@target(javascript)
fn " <> mount <> "_mount_navigate(
  config config: " <> config <> "(shared_state),
  model model: " <> model <> "(shared_state),
  path path: String,
  push_history push_history: Bool,
) -> #(" <> model <> "(shared_state), Effect(" <> msg <> ")) {
  let route = " <> routes <> ".parse_path(path)
  let canonical_path = " <> routes <> ".route_to_path(route)
  let shared_state = config.set_active_path(model.shared_state, canonical_path)
  let page_context = config.page_context(shared_state)
  let #(page, page_effect) =
    " <> mount <> "_load_client(
      page_context:,
      query_params: " <> page_input <> ".empty_query_params(),
      route:,
    )

  #(
    " <> model <> "(page: page, shared_state:),
    effect.batch([
      navigation_effects(
        path: canonical_path,
        push_history: push_history,
        page_effect: page_effect,
        on_page: " <> page_msg <> ",
      ),
      sync_topics(" <> mount <> "_page_topics(page)),
    ]),
  )
}
"
}

fn browser_app_int_import(loads: List(LoadRpc)) -> String {
  case
    list.any(loads, fn(load) {
      list.any(load.args, fn(arg) { arg.type_ref == "Int" })
    })
  {
    True -> "@target(javascript)\nimport gleam/int\n"
    False -> ""
  }
}

fn browser_app_list_import(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(_) -> "@target(javascript)\nimport gleam/list\n"
    None -> ""
  }
}

fn browser_app_client_protocol_import(
  push_contract: Option(PushContract),
) -> String {
  case push_contract {
    Some(_) -> "@target(javascript)\nimport generated/rally/client_protocol\n"
    None -> ""
  }
}

fn browser_app_page_imports(loads: List(LoadRpc)) -> String {
  let page_modules =
    loads
    |> list.filter(fn(load) { load.module_path != load.wire_module })
    |> list.map(fn(load) { load.module_path })
  let navigation_modules =
    loads
    |> list.flat_map(fn(load) {
      list.map(load.navigation_sources, fn(navigation) {
        navigation.message_module
      })
    })
  let route_modules =
    loads
    |> list.flat_map(fn(load) { load.route_modules })

  list.append(page_modules, list.append(navigation_modules, route_modules))
  |> list.unique
  |> list.filter(fn(module_path) {
    !list.any(loads, fn(load) {
      load.module_path == module_path && load.module_path == load.wire_module
    })
  })
  |> list.map(fn(module_path) {
    "@target(javascript)\nimport "
    <> module_path
    <> " as "
    <> browser_app_source_page_alias(module_path, loads)
  })
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn browser_app_server_frame_effect(
  push_contract: Option(PushContract),
) -> String {
  case push_contract {
    Some(contract) -> "@target(javascript)
pub fn server_frame_effect(
  page page: page,
  bytes bytes: BitArray,
  apply_push apply_push: fn(page, String, " <> push_type_ref(contract) <> ") ->
    #(page, Effect(page_msg)),
  on_page on_page: fn(page_msg) -> msg,
) -> #(page, Effect(msg)) {
  case client_protocol.decode_server_frame(bytes) {
    Ok(client_protocol.Push(module:, message:)) ->
      map_page_effect(apply_push(page, module, message), on_page)
    Error(Nil) -> #(page, effect.none())
  }
}
"
    None ->
      "@target(javascript)
pub fn server_frame_effect(
  page page: page,
  bytes _bytes: BitArray,
  apply_push _apply_push: fn(page, String, Nil) -> #(page, Effect(page_msg)),
  on_page _on_page: fn(page_msg) -> msg,
) -> #(page, Effect(msg)) {
  #(page, effect.none())
}
"
  }
}

fn browser_app_mount_load_route_type(
  mount: String,
  loads: List(LoadRpc),
) -> String {
  let prefix = mount_type_prefix(mount)
  let pages = mount_alias(mount, "pages")

  "@target(javascript)
pub type " <> prefix <> "LoadRoute {
  " <> prefix <> "NoLoad
" <> string.join(list.map(loads, fn(load) { "  " <> pascal_name(load) <> "Load(
    " <> browser_app_load_message_field(load) <> "to_message: fn(Result(" <> wire_alias(
      load,
    ) <> ".LoadResult, List(ApiLoadError))) -> " <> pages <> ".Message,
  )" }), "\n") <> "
}
"
}

fn browser_app_load_message_field(load: LoadRpc) -> String {
  case load.import_on_client {
    True -> ""
    False -> "message: " <> wire_alias(load) <> ".ServerMsg,\n    "
  }
}

fn browser_app_mount_topic_functions(
  mount: String,
  loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
) -> String {
  let pages = mount_alias(mount, "pages")
  let route_modules = mount_route_modules(loads)
  let topic_type = case push_contract {
    Some(_) -> "push_payload.Topic"
    None -> "String"
  }

  "@target(javascript)
pub fn " <> mount <> "_page_topics(page page: " <> pages <> ".Page) -> List(" <> topic_type <> ") {
  case page {
" <> string.join(
    list.map(route_modules, fn(module_path) {
      "    " <> browser_app_page_pattern(pages, module_path) <> " ->
      " <> browser_app_source_page_alias(module_path, loads) <> browser_app_topics_call(
        module_path,
      )
    }),
    "\n",
  ) <> "
    _ -> []
  }
}
" <> browser_app_mount_apply_push(mount, loads, route_modules, push_contract:)
}

fn browser_app_sync_topics(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(_) ->
      "@target(javascript)
pub fn sync_topics(topics topics: List(push_payload.Topic)) -> Effect(msg) {
  client_transport.sync_topics(list.map(topics, push_payload.topic_name))
}
"
    None ->
      "@target(javascript)
pub fn sync_topics(topics topics: List(String)) -> Effect(msg) {
  client_transport.sync_topics(topics)
}
"
  }
}

fn browser_app_mount_apply_push(
  mount: String,
  loads: List(LoadRpc),
  route_modules: List(String),
  push_contract push_contract: Option(PushContract),
) -> String {
  let pages = mount_alias(mount, "pages")

  case push_contract {
    Some(contract) -> "
@target(javascript)
pub fn " <> mount <> "_apply_push(
  page page: " <> pages <> ".Page,
  module _module: String,
  message message: " <> push_type_ref(contract) <> ",
) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  case page {
" <> string.join(
        list.map(route_modules, fn(module_path) {
          let constructor = route_constructor_for_module(module_path)
          let page = browser_app_source_page_alias(module_path, loads)
          "    " <> browser_app_page_pattern(pages, module_path) <> " -> {
      let #(model, page_effect) = " <> page <> ".apply_push(model, message)
      #(" <> browser_app_page_constructor(
            pages,
            constructor,
            module_path,
            "model",
          ) <> ", effect.map(page_effect, " <> pages <> "." <> route_message_constructor(
            module_path,
          ) <> "))
    }"
        }),
        "\n",
      ) <> "
    _ -> #(page, effect.none())
  }
}
"
    None -> "
@target(javascript)
pub fn " <> mount <> "_apply_push(
  page page: " <> pages <> ".Page,
  module _module: String,
  message _message: Nil,
) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  #(page, effect.none())
}
"
  }
}

fn browser_app_page_pattern(pages: String, module_path: String) -> String {
  let constructor = route_constructor_for_module(module_path)
  case dynamic_segments_from_module(module_path) {
    [] -> pages <> "." <> constructor <> "Page(model)"
    _ -> pages <> "." <> constructor <> "Page(route_params:, model:)"
  }
}

fn browser_app_page_constructor(
  pages: String,
  constructor: String,
  module_path: String,
  model: String,
) -> String {
  case dynamic_segments_from_module(module_path) {
    [] -> pages <> "." <> constructor <> "Page(" <> model <> ")"
    _ ->
      pages
      <> "."
      <> constructor
      <> "Page(route_params:, model: "
      <> model
      <> ")"
  }
}

fn browser_app_topics_call(module_path: String) -> String {
  case dynamic_segments_from_module(module_path) {
    [] -> ".topics(model)"
    _ -> ".topics(route_params, model)"
  }
}

fn mount_route_modules(loads: List(LoadRpc)) -> List(String) {
  loads
  |> list.flat_map(fn(load) { load.route_modules })
  |> list.unique
}

fn browser_app_mount_initial_page(
  mount: String,
  loads: List(LoadRpc),
) -> String {
  let prefix = mount_type_prefix(mount)
  let page_input = mount_alias(mount, "page_input")
  let pages = mount_alias(mount, "pages")
  let routes = mount_alias(mount, "routes")
  let request_route_label = case browser_app_mount_uses_route(loads) {
    True -> "route"
    False -> "_route"
  }

  "@target(javascript)
pub fn " <> mount <> "_load_client(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  route route: " <> routes <> ".Route,
) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  let page = " <> pages <> ".load_sync(page_context, query_params, route)
  #(page, " <> mount <> "_request_effect(route, " <> mount <> "_load_route(route)))
}

@target(javascript)
pub fn " <> mount <> "_load_path(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  path path: String,
) -> #(String, " <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  let route = " <> routes <> ".parse_path(path)
  let canonical_path = " <> routes <> ".route_to_path(route)
  let #(page, page_effect) =
    " <> mount <> "_load_client(page_context:, query_params:, route:)
  #(canonical_path, page, page_effect)
}

@target(javascript)
pub fn " <> mount <> "_initial_page(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  route route: " <> routes <> ".Route,
  update_page update_page: fn(PageContext, " <> pages <> ".Page, " <> pages <> ".Message) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)),
) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  let page = " <> pages <> ".load_sync(page_context, query_params, route)

  case " <> mount <> "_load_route(route) {
    " <> prefix <> "NoLoad -> #(page, effect.none())
" <> string.join(list.map(loads, browser_app_initial_page_case), "\n") <> "
  }
}

@target(javascript)
pub fn " <> mount <> "_initial_page_from_path(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  path path: String,
  update_page update_page: fn(PageContext, " <> pages <> ".Page, " <> pages <> ".Message) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)),
) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)) {
  " <> mount <> "_initial_page(
    page_context:,
    query_params:,
    route: " <> routes <> ".parse_path(path),
    update_page:,
  )
}

@target(javascript)
fn " <> mount <> "_request_effect(
  route " <> request_route_label <> ": " <> routes <> ".Route,
  selected selected: " <> prefix <> "LoadRoute,
) -> Effect(" <> pages <> ".Message) {
  case selected {
    " <> prefix <> "NoLoad -> effect.none()
" <> string.join(list.map(loads, browser_app_request_effect_case), "\n") <> "
  }
}
"
}

fn browser_app_mount_navigation_functions(
  mount: String,
  loads: List(LoadRpc),
) -> String {
  let pages = mount_alias(mount, "pages")

  "@target(javascript)
pub fn " <> mount <> "_message_path(message message: " <> pages <> ".Message) -> Option(String) {
  case message {
" <> string.join(
    list.flat_map(loads, fn(load) { browser_app_navigation_cases(load, loads) }),
    "\n",
  ) <> "
    _ -> None
  }
}
"
}

fn browser_app_navigation_cases(
  load: LoadRpc,
  loads: List(LoadRpc),
) -> List(String) {
  load.navigation_sources
  |> list.map(fn(navigation) {
    "    "
    <> mount_alias(load_mount(load), "pages")
    <> "."
    <> route_message_constructor(navigation.source_module)
    <> "("
    <> browser_app_navigation_message_pattern(loads, navigation)
    <> ") -> Some("
    <> mount_alias(load_mount(load), "routes")
    <> ".route_to_path("
    <> browser_app_navigation_route(load, navigation)
    <> "))"
  })
}

fn browser_app_navigation_message_pattern(
  loads: List(LoadRpc),
  navigation: PageNavigation,
) -> String {
  browser_app_source_page_alias(navigation.message_module, loads)
  <> "."
  <> navigation.message_constructor
  <> browser_app_navigation_pattern_args(navigation.args)
}

fn browser_app_navigation_pattern_args(args: List(LoadArg)) -> String {
  case args {
    [] -> ""
    _ ->
      "("
      <> string.join(list.map(args, fn(arg) { arg.label <> ":" }), ", ")
      <> ")"
  }
}

fn browser_app_navigation_route(
  load: LoadRpc,
  navigation: PageNavigation,
) -> String {
  let route_args =
    list.zip(dynamic_segments_from_module(load.module_path), navigation.args)
    |> list.map(fn(pair) {
      let #(route_field, arg) = pair
      route_field <> ": " <> browser_app_navigation_route_arg(arg)
    })

  mount_alias(load_mount(load), "routes")
  <> "."
  <> route_constructor_for_module(load.module_path)
  <> case route_args {
    [] -> ""
    _ -> "(" <> string.join(route_args, ", ") <> ")"
  }
}

fn browser_app_navigation_route_arg(arg: LoadArg) -> String {
  case arg.type_ref {
    "Int" -> "int.to_string(" <> arg.label <> ")"
    _ -> arg.label
  }
}

fn browser_app_source_page_alias(
  module_path: String,
  loads: List(LoadRpc),
) -> String {
  case list.find(loads, fn(load) { load.module_path == module_path }) {
    Ok(load) ->
      case load.module_path == load.wire_module {
        True -> wire_alias(load)
        False -> page_alias(load)
      }
    Error(Nil) -> page_module_alias(module_path)
  }
}

fn browser_app_mount_load_route_function(
  mount: String,
  loads: List(LoadRpc),
) -> String {
  let prefix = mount_type_prefix(mount)
  let routes = mount_alias(mount, "routes")

  "@target(javascript)
pub fn " <> mount <> "_load_route(route route: " <> routes <> ".Route) -> " <> prefix <> "LoadRoute {
  case route {
" <> string.join(list.flat_map(loads, browser_app_load_route_cases), "\n") <> "
    _ -> " <> prefix <> "NoLoad
  }
}
"
}

fn browser_app_load_route_cases(load: LoadRpc) -> List(String) {
  load.route_modules
  |> list.map(fn(route_module) {
    "    "
    <> browser_app_route_module_pattern(route_module)
    <> " -> "
    <> browser_app_load_route_body(load, route_module)
  })
}

fn browser_app_load_route_body(load: LoadRpc, route_module: String) -> String {
  case load.import_on_client, load.args {
    False, [] -> browser_app_load_route_constructor(load, route_module, "")
    False, _ -> browser_app_load_route_arg_body(load, route_module)
    True, _ -> browser_app_load_route_constructor(load, route_module, "")
  }
}

fn browser_app_load_route_arg_body(
  load: LoadRpc,
  route_module: String,
) -> String {
  let args = browser_app_route_args(load)
  let route_fields = list.map(args, fn(pair) { pair.0 })
  let load_args = list.map(args, fn(pair) { pair.1 })

  case browser_app_supported_route_args(load) {
    False -> mount_type_prefix(load_mount(load)) <> "NoLoad"
    True -> {
      let parsers =
        list.zip(route_fields, load_args)
        |> list.map(fn(pair) {
          let #(route_field, arg) = pair
          case arg.type_ref {
            "Int" -> Some("case int.parse(" <> route_field <> ") {
          Ok(" <> arg.label <> ") -> ")
            _ -> None
          }
        })
        |> option.values
      case parsers {
        [] ->
          browser_app_load_route_constructor(
            load,
            route_module,
            load_args
              |> list.map(fn(arg) { arg.label <> ":" })
              |> string.join(", "),
          )
        _ -> {
          let close_parens =
            list.repeat("}", list.length(parsers))
            |> string.join("\n")
          let load_arg_labels =
            load_args
            |> list.map(fn(arg) { arg.label <> ":" })
            |> string.join(", ")
          let no_load = mount_type_prefix(load_mount(load)) <> "NoLoad"

          string.join(parsers, "")
          <> browser_app_load_route_constructor(
            load,
            route_module,
            load_arg_labels,
          )
          <> "
          Error(Nil) -> "
          <> no_load
          <> "
        "
          <> close_parens
        }
      }
    }
  }
}

fn browser_app_load_route_constructor(
  load: LoadRpc,
  route_module: String,
  message_args: String,
) -> String {
  pascal_name(load)
  <> "Load("
  <> browser_app_load_route_message(load, message_args)
  <> "to_message: fn(result) { "
  <> browser_app_load_result_message(load, route_module)
  <> " })"
}

fn browser_app_load_route_message(
  load: LoadRpc,
  message_args: String,
) -> String {
  case load.import_on_client {
    True -> ""
    False ->
      "message: "
      <> wire_alias(load)
      <> "."
      <> load.request_constructor
      <> browser_app_constructor_args(message_args)
      <> ", "
  }
}

fn browser_app_constructor_args(args: String) -> String {
  case args {
    "" -> ""
    _ -> "(" <> args <> ")"
  }
}

fn browser_app_load_result_message(
  load: LoadRpc,
  route_module: String,
) -> String {
  let pages = mount_alias(load_mount(load), "pages")
  let message = route_message_constructor(route_module)
  let page = page_alias(load)
  let wire = wire_alias(load)

  "case result {
      Ok(" <> wire <> "." <> load.load_result_constructor <> "(data)) ->
        " <> pages <> "." <> message <> "(" <> page <> ".Loaded(Ok(data)))
      Error(errors) ->
        " <> pages <> "." <> message <> "(" <> page <> ".Loaded(Error(" <> page <> ".LoadError(message: api_load_error(errors)))))
    }"
}

fn browser_app_route_module_pattern(route_module: String) -> String {
  let mount = load_mount_from_module(route_module)
  mount_alias(mount, "routes")
  <> "."
  <> route_constructor_for_module(route_module)
  <> browser_app_route_module_pattern_args(route_module)
}

fn browser_app_route_module_pattern_args(route_module: String) -> String {
  route_module
  |> dynamic_segments_from_module
  |> list.map(fn(segment) { segment <> ":" })
  |> fn(args) {
    case args {
      [] -> ""
      _ -> "(" <> string.join(args, ", ") <> ")"
    }
  }
}

fn browser_app_initial_page_case(load: LoadRpc) -> String {
  "    "
  <> pascal_name(load)
  <> "Load("
  <> browser_app_ignored_load_message_pattern(load)
  <> "to_message:) -> {
      initial_loaded_page(
        page: page,
        page_context: page_context,
        hydration: hydration."
  <> load.name
  <> "_load_result(),
        to_message: to_message,
        load_client: fn() { "
  <> load_mount(load)
  <> "_request_effect(route, "
  <> load_mount(load)
  <> "_load_route(route)) },
        update_page: update_page,
      )
    }"
}

fn browser_app_request_effect_case(load: LoadRpc) -> String {
  "    "
  <> pascal_name(load)
  <> "Load("
  <> browser_app_load_message_pattern(load)
  <> "to_message:) -> "
  <> browser_app_send_load(load)
}

fn browser_app_load_message_pattern(load: LoadRpc) -> String {
  case load.import_on_client {
    True -> ""
    False -> "message:, "
  }
}

fn browser_app_ignored_load_message_pattern(load: LoadRpc) -> String {
  case load.import_on_client {
    True -> ""
    False -> "message: _, "
  }
}

fn browser_app_mount_uses_route(loads: List(LoadRpc)) -> Bool {
  list.any(loads, fn(load) {
    browser_app_supported_route_args(load) && !list.is_empty(load.args)
  })
}

fn browser_app_send_load(load: LoadRpc) -> String {
  case browser_app_supported_route_args(load) {
    False -> "effect.none()"
    True -> {
      case load.args {
        [] -> browser_app_transport_call(load)
        _ -> "case route {
        " <> browser_app_route_pattern(load) <> " -> " <> browser_app_send_load_arg_body(
            load,
          ) <> "
        _ -> effect.none()
      }"
      }
    }
  }
}

fn browser_app_send_load_arg_body(load: LoadRpc) -> String {
  case load.import_on_client {
    False -> browser_app_transport_call(load)
    True -> browser_app_send_load_arg_body_from_route(load)
  }
}

fn browser_app_send_load_arg_body_from_route(load: LoadRpc) -> String {
  let args = browser_app_route_args(load)
  let route_fields = list.map(args, fn(pair) { pair.0 })
  let load_args = list.map(args, fn(pair) { pair.1 })

  case list.any(load_args, fn(arg) { arg.type_ref == "Int" }) {
    False -> browser_app_transport_call(load)
    True -> browser_app_int_load_arg_body(load, route_fields, load_args)
  }
}

fn browser_app_int_load_arg_body(
  load: LoadRpc,
  route_fields: List(String),
  load_args: List(LoadArg),
) -> String {
  let parsers =
    list.zip(route_fields, load_args)
    |> list.map(fn(pair) {
      let #(route_field, arg) = pair
      case arg.type_ref {
        "Int" -> Some("case int.parse(" <> route_field <> ") {
            Ok(" <> arg.label <> ") -> ")
        _ -> None
      }
    })
    |> option.values

  let close_parens =
    list.repeat("}", list.length(parsers))
    |> string.join("\n")

  string.join(parsers, "") <> browser_app_transport_call(load) <> "
            Error(Nil) -> effect.none()
          " <> close_parens
}

fn browser_app_transport_call(load: LoadRpc) -> String {
  "client_transport.send_"
  <> load.name
  <> "_load("
  <> browser_app_transport_call_args(load)
  <> "on_result: to_message)"
}

fn browser_app_transport_call_args(load: LoadRpc) -> String {
  let args = case load.import_on_client {
    True -> load.args |> list.map(fn(arg) { arg.label <> ":" })
    False -> ["message:"]
  }

  case args {
    [] -> ""
    _ -> string.join(args, ", ") <> ", "
  }
}

fn browser_app_supported_route_args(load: LoadRpc) -> Bool {
  let route_args = browser_app_route_args(load)

  list.length(route_args) == list.length(load.args)
  && list.all(route_args, fn(pair) {
    let #(route_field, arg) = pair
    case arg.type_ref {
      "Int" -> True
      "String" -> route_field == arg.label
      _ -> False
    }
  })
}

fn browser_app_route_pattern(load: LoadRpc) -> String {
  mount_alias(load_mount(load), "routes")
  <> "."
  <> server_ssr_route_constructor(load)
  <> browser_app_route_pattern_args(load)
}

fn browser_app_route_pattern_args(load: LoadRpc) -> String {
  let args =
    browser_app_route_args(load)
    |> list.map(fn(pair) {
      case load.import_on_client {
        True -> pair.0 <> ":"
        False -> pair.0 <> ": _"
      }
    })

  case args {
    [] -> ""
    _ -> "(" <> string.join(args, ", ") <> ")"
  }
}

fn browser_app_route_args(load: LoadRpc) -> List(#(String, LoadArg)) {
  list.zip(server_ssr_dynamic_segments(load), load.args)
}

pub fn client_protocol(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
) -> String {
  "@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import generated/libero/etf as libero_etf
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> push_import(
    push_contract,
    "@target(javascript)",
  ) <> "
" <> client_server_frame_type(push_contract) <> "

" <> string.join(list.map(loads, client_encode_request), "\n") <> "
" <> client_decode_server_frame(push_contract) <> "

" <> string.join(list.map(loads, client_decode_load_result), "\n") <> "
" <> string.join(
    option.values(list.map(loads, client_decode_save_result)),
    "\n",
  ) <> "

@target(javascript)
pub fn decode_result_envelope(bytes: BitArray) -> Result(#(Int, a), Nil) {
  case bytes {
    <<2, payload:bits>> -> decode_any(payload)
    _ -> Error(Nil)
  }
}

@target(javascript)
fn encode_any(value: a) -> BitArray {
  libero_etf.encode(value)
}

@target(javascript)
fn decode_any(bytes: BitArray) -> Result(a, Nil) {
  case libero_etf.decode(bytes) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}
"
}

pub fn server_protocol(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
) -> String {
  "@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(erlang)
import generated/libero/etf as libero_etf
" <> wire_imports(loads, "@target(erlang)", client_only: False) <> push_import(
    push_contract,
    "@target(erlang)",
  ) <> "

@target(erlang)
pub fn ensure() -> Nil {
  libero_etf.ensure()
}

" <> string.join(list.map(loads, server_request_type), "\n") <> "
" <> string.join(list.map(loads, server_decode_request), "\n") <> "
" <> string.join(list.map(loads, server_encode_load_result), "\n") <> "
" <> string.join(
    option.values(list.map(loads, server_encode_save_result)),
    "\n",
  ) <> "
" <> string.join(list.map(loads, server_load_result_encoder), "\n") <> "
" <> string.join(
    option.values(list.map(loads, server_save_result_encoder)),
    "\n",
  ) <> "

" <> server_protocol_push_helpers(push_contract) <> "

@target(erlang)
fn encode_result_frame(request_id: Int, result: a) -> BitArray {
  let payload = encode_any(#(request_id, result))
  <<2, payload:bits>>
}

@target(erlang)
fn encode_ok_payload(result: Result(a, b), encode_ok: fn(a) -> c) -> Result(c, b) {
  case result {
    Ok(payload) -> Ok(encode_ok(payload))
    Error(error) -> Error(error)
  }
}

@target(erlang)
fn decode_any(bytes: BitArray) -> Result(a, Nil) {
  case libero_etf.decode(bytes) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

@target(erlang)
fn encode_any(value: a) -> BitArray {
  libero_etf.encode(value)
}
"
}

pub fn client_transport(loads loads: List(LoadRpc)) -> String {
  "@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/rally/result.{type ApiLoadError, type ApiSaveError}
@target(javascript)
import lustre/effect.{type Effect}
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
@target(javascript)
pub fn connect(
  url url: String,
  on_frame on_frame: fn(BitArray) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    connect_socket(url, fn(frame) { dispatch(on_frame(frame)) })
  })
}

" <> string.join(list.map(loads, transport_send_load), "\n") <> "
" <> string.join(option.values(list.map(loads, transport_send_save)), "\n") <> "

@target(javascript)
pub fn sync_topics(topics topics: List(String)) -> Effect(msg) {
  effect.from(fn(_dispatch) { send_topic_frame(topics) })
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"connect\")
fn connect_socket(_url: String, _on_frame: fn(BitArray) -> Nil) -> Nil {
  Nil
}

" <> string.join(list.map(loads, transport_external), "\n") <> "
" <> string.join(option.values(list.map(loads, transport_save_external)), "\n") <> "

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_topic_frame\")
fn send_topic_frame(_topics: List(String)) -> Nil {
  Nil
}

@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"next_request_id\")
fn next_request_id() -> Int {
  0
}
"
}

pub fn page_server(loads loads: List(LoadRpc)) -> String {
  "@target(javascript)
import generated/rally/client_transport
@target(javascript)
import generated/rally/result as transport_result
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option}
@target(javascript)
import lustre/effect.{type Effect}
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
@target(erlang)
pub fn ensure() -> Nil {
  Nil
}

@target(javascript)
pub type LoadError {
  LoadError(message: String)
}

@target(javascript)
pub type SaveError {
  SaveError(field: Option(String), message: String)
}

" <> string.join(list.map(loads, page_server_load), "\n") <> "
" <> string.join(option.values(list.map(loads, page_server_save)), "\n") <> "

@target(javascript)
fn map_load_result(
  result: Result(a, List(transport_result.ApiLoadError)),
) -> Result(a, List(LoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let transport_result.ApiLoadError(message:) = error
      LoadError(message:)
    }))
  }
}

@target(javascript)
fn map_save_result(
  result: Result(a, List(transport_result.ApiSaveError)),
) -> Result(a, List(SaveError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let transport_result.ApiSaveError(field:, message:) = error
      SaveError(field:, message:)
    }))
  }
}
"
}

pub fn server_ws(
  loads loads: List(LoadRpc),
  push_contract push_contract: Option(PushContract),
  load_context load_context: Option(LoadContext),
) -> String {
  "@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
import generated/rally/result as transport_result
@target(erlang)
import generated/rally/server_protocol
@target(erlang)
import gleam/erlang/process.{type Selector}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/string
@target(erlang)
import mist.{type Next, type WebsocketConnection, type WebsocketMessage}
@target(erlang)
import rally/runtime/topics
" <> wire_imports(loads, "@target(erlang)", client_only: False) <> server_ws_page_imports(
    loads,
    load_context:,
  ) <> server_ws_load_context_import(loads, load_context:) <> push_import(
    push_contract,
    "@target(erlang)",
  ) <> "
@target(erlang)
pub type LoadError {
  LoadError(message: String)
}

@target(erlang)
pub type SaveError {
  SaveError(field: Option(String), message: String)
}

@target(erlang)
pub type " <> server_ws_handlers_type_definition(loads, load_context:) <> " {
  Handlers(
" <> server_ws_handler_fields(loads, load_context:) <> "
  )
}
" <> server_ws_transport_loop(load_context) <> "

@target(erlang)
pub fn handle_client_frame(
  state state: state,
  conn conn: WebsocketConnection,
  data data: BitArray,
  handlers handlers: " <> server_ws_handlers_type(loads, load_context:) <> ",
) -> Nil {
  server_protocol.ensure()
  " <> server_ws_dispatch_cases(loads) <> "
}
" <> server_ws_sync_topic_frame() <> "
" <> server_ws_push_frame(push_contract) <> "

" <> string.join(
    list.map(loads, fn(load) {
      server_ws_try_request(load, loads, load_context:)
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(loads, fn(load) {
      server_ws_send_load_result(load, loads, load_context:)
    }),
    "\n",
  ) <> "
" <> string.join(
    option.values(
      list.map(loads, fn(load) {
        server_ws_send_save_result(load, loads, load_context:, push_contract:)
      }),
    ),
    "\n",
  ) <> "
" <> server_ws_map_page_load_result(loads, load_context:) <> "
@target(erlang)
fn map_load_result(
  result: Result(a, List(LoadError)),
) -> Result(a, List(transport_result.ApiLoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let LoadError(message:) = error
      transport_result.ApiLoadError(message:)
    }))
  }
}

@target(erlang)
fn map_save_result(
  result: Result(a, List(SaveError)),
) -> Result(a, List(transport_result.ApiSaveError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      let SaveError(field:, message:) = error
      transport_result.ApiSaveError(field:, message:)
    }))
  }
}
"
}

pub fn server_ssr(
  loads loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let mounts = load_mounts(loads)
  let direct_loads = server_ssr_direct_loads(loads, load_context:)

  "@target(javascript)
pub fn ensure() -> Nil {
  Nil
}

@target(erlang)
import generated/rally/result as transport_result
@target(erlang)
import generated/rally/server_protocol
@target(erlang)
import gleam/bit_array
" <> server_ssr_int_import(direct_loads) <> "@target(erlang)
import gleam/list
@target(erlang)
import lustre/effect.{type Effect}
@target(erlang)
import lustre/element.{type Element}
@target(erlang)
import page_context.{type PageContext}
" <> server_ssr_mount_imports(mounts) <> wire_imports(
    loads,
    "@target(erlang)",
    client_only: False,
  ) <> server_ssr_page_imports(direct_loads) <> server_ssr_load_context_import(
    direct_loads,
    load_context:,
  ) <> "\n" <> string.join(
    list.map(mounts, fn(mount) { server_ssr_mount_output_type(mount) }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      server_ssr_mount_route_type(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      server_ssr_mount_load_route_function(mount, mount_loads(loads, mount))
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      server_ssr_mount_handlers_type(
        mount,
        mount_loads(loads, mount),
        load_context:,
      )
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      server_ssr_mount_render_path(
        mount,
        mount_loads(loads, mount),
        load_context:,
      )
    }),
    "\n",
  ) <> "
" <> string.join(
    list.map(mounts, fn(mount) {
      server_ssr_mount_boot_page(
        mount,
        mount_loads(loads, mount),
        load_context:,
      )
    }),
    "\n",
  ) <> "
" <> string.join(list.map(loads, server_ssr_hydration_payload), "\n") <> "

@target(erlang)
fn map_load_result(
  result: Result(a, List(String)),
) -> Result(a, List(transport_result.ApiLoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) -> Error(list.map(errors, fn(error) {
      transport_result.ApiLoadError(message: error)
    }))
  }
}

@target(erlang)
fn boot_loaded_page(
  page page: page,
  result result: Result(load_result, List(String)),
  hydration_payload hydration_payload: fn(Result(load_result, List(String))) -> String,
  to_message to_message: fn(Result(load_result, List(String))) -> message,
  update_page update_page: fn(page, message) -> #(page, Effect(message)),
) -> #(page, List(String)) {
  let #(page, _) = update_page(page, to_message(result))
  #(page, [hydration_payload(result)])
}
"
}

pub fn hydration(loads loads: List(LoadRpc)) -> String {
  "@target(javascript)
import generated/rally/client_protocol
@target(javascript)
import generated/rally/result.{type ApiLoadError}
@target(javascript)
import generated/rally/browser
@target(javascript)
import gleam/bit_array
@target(javascript)
import gleam/string
" <> wire_imports(loads, "@target(javascript)", client_only: True) <> "
" <> string.join(list.map(loads, hydration_load_result), "\n") <> "
" <> string.join(list.map(loads, hydration_decode_result), "\n")
}

fn source_module_from_file(
  src_root: String,
  path: String,
) -> Result(SourceModule, String) {
  use source <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(e) {
      "Cannot read " <> path <> ": " <> simplifile.describe_error(e)
    }),
  )
  let source_module = module_from_path(src_root, path)
  let is_wire = string.ends_with(source_module, "/wire")
  let module_path = case is_wire {
    True -> string.drop_end(source_module, string.length("/wire"))
    False -> source_module
  }
  use ast <- result.try(
    glance.module(source)
    |> result.map_error(fn(_) { "Cannot parse " <> source_module }),
  )
  use resolver <- result.try(
    glance_type_resolver.resolver_from_imports(ast.imports)
    |> result.map_error(fn(_) { "Cannot resolve imports for " <> source_module }),
  )
  Ok(SourceModule(
    source_module:,
    module_path:,
    wire_module: source_module,
    import_on_client: is_wire,
    ast:,
    resolver:,
  ))
}

fn discover_source_module(
  info info: SourceModule,
  modules modules: List(SourceModule),
) -> Result(List(LoadRpc), String) {
  discover_source(
    module_path: info.module_path,
    wire_module: info.wire_module,
    import_on_client: info.import_on_client,
    ast: info.ast,
    resolver: info.resolver,
    modules:,
  )
}

fn discover_source(
  module_path module_path: String,
  wire_module wire_module: String,
  import_on_client import_on_client: Bool,
  ast ast: glance.Module,
  resolver resolver: TypeResolver,
  modules modules: List(SourceModule),
) -> Result(List(LoadRpc), String) {
  case has_custom_type(ast.custom_types, "LoadResult") {
    False -> Ok([])
    True -> {
      case
        list.find(ast.custom_types, fn(def) {
          def.definition.name == "ServerMsg"
        })
      {
        Error(Nil) -> Ok([])
        Ok(def) -> {
          let has_save_message =
            list.any(def.definition.variants, fn(variant) {
              !string.ends_with(variant.name, "Load")
            })
          let save_result_type = case
            import_on_client,
            has_custom_type(ast.custom_types, "GameUpdate"),
            has_save_message
          {
            False, True, True -> Some("GameUpdate")
            _, _, _ -> None
          }
          use _ <- result.try(validate_wire_boundary(
            ast:,
            resolver:,
            module_path:,
            wire_module:,
            save_result_type:,
            modules:,
          ))
          let load_variants =
            def.definition.variants
            |> list.filter(fn(variant) {
              string.ends_with(variant.name, "Load")
            })
          use load_result_constructor <- result.try(load_result_constructor(
            ast.custom_types,
          ))

          load_variants
          |> list.try_map(fn(variant) {
            let name =
              variant.name
              |> string.drop_end(string.length("Load"))
              |> to_snake_case
            use args <- result.try(load_args(
              fields: variant.fields,
              resolver: resolver,
              module_path: wire_module,
              variant_name: variant.name,
            ))
            Ok(LoadRpc(
              name:,
              module_path:,
              wire_module:,
              import_on_client:,
              request_constructor: variant.name,
              load_result_constructor:,
              route_modules: [module_path],
              navigation_sources: [],
              update_uses_page_context: False,
              args:,
              save_result_type:,
            ))
          })
        }
      }
    }
  }
}

fn load_route_modules(
  load: LoadRpc,
  modules: List(SourceModule),
) -> List(String) {
  [
    load.module_path,
    ..modules
    |> list.filter_map(fn(info) {
      case source_module_aliases_load(info, load.module_path) {
        True -> Ok(info.module_path)
        False -> Error(Nil)
      }
    })
  ]
  |> list.unique
}

fn source_module_aliases_load(info: SourceModule, load_module: String) -> Bool {
  info.module_path != load_module
  && load_mount_from_module(info.module_path)
  == load_mount_from_module(load_module)
  && type_alias_targets_module(info, "Model", load_module)
  && type_alias_targets_module(info, "Message", load_module)
}

fn navigation_sources(
  load: LoadRpc,
  modules: List(SourceModule),
) -> List(PageNavigation) {
  let constructor = navigation_message_constructor(load.module_path)

  modules
  |> list.filter_map(fn(source) {
    case load_mount_from_module(source.module_path) == load_mount(load) {
      True -> Ok(Nil)
      False -> Error(Nil)
    }
    |> result.try(fn(_) {
      use message_module <- result.try(source_message_module(source))
      use message_source <- result.try(find_source_module(
        modules,
        message_module,
      ))
      use message_type <- result.try(find_custom_type(
        message_source.ast.custom_types,
        "Message",
      ))
      use variant <- result.try(
        list.find(message_type.definition.variants, fn(variant) {
          variant.name == constructor
        }),
      )
      use args <- result.try(navigation_args(
        load:,
        source: message_source,
        fields: variant.fields,
      ))
      Ok(PageNavigation(
        source_module: source.module_path,
        message_module:,
        message_constructor: constructor,
        args:,
      ))
    })
  })
}

fn source_message_module(source: SourceModule) -> Result(String, Nil) {
  case has_custom_type(source.ast.custom_types, "Message") {
    True -> Ok(source.module_path)
    False -> message_alias_module(source)
  }
}

fn message_alias_module(source: SourceModule) -> Result(String, Nil) {
  case
    list.find(source.ast.type_aliases, fn(def) {
      def.definition.name == "Message"
    })
  {
    Ok(def) ->
      case
        glance_type_resolver.type_to_field_type(
          type_: def.definition.aliased,
          resolver: source.resolver,
          current_module: source.module_path,
          policy: glance_type_resolver.PreserveUnsupported,
        )
      {
        Ok(field_type.UserType(module_path:, type_name: "Message", args: [])) ->
          Ok(module_path)
        _ -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

fn navigation_args(
  load load: LoadRpc,
  source source: SourceModule,
  fields fields: List(glance.VariantField),
) -> Result(List(LoadArg), Nil) {
  let route_args = dynamic_segments_from_module(load.module_path)
  use _ <- result.try(case list.length(route_args) == list.length(fields) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })

  fields
  |> list.try_map(fn(field) {
    let #(label, type_) = variant_field_label_and_type(field)
    use _ <- result.try(case list.contains(route_args, label) {
      True -> Ok(Nil)
      False -> Error(Nil)
    })
    case
      glance_type_resolver.type_to_field_type(
        type_:,
        resolver: source.resolver,
        current_module: source.module_path,
        policy: glance_type_resolver.PreserveUnsupported,
      )
    {
      Ok(field_type.IntField) -> Ok(LoadArg(label:, type_ref: "Int"))
      Ok(field_type.StringField) -> Ok(LoadArg(label:, type_ref: "String"))
      _ -> Error(Nil)
    }
  })
}

fn mount_update_uses_page_context(
  load: LoadRpc,
  modules: List(SourceModule),
) -> Bool {
  modules
  |> list.any(fn(source) {
    load_mount_from_module(source.module_path) == load_mount(load)
    && source_update_uses_page_context(source)
  })
}

fn source_update_uses_page_context(source: SourceModule) -> Bool {
  case
    list.find(source.ast.functions, fn(def) { def.definition.name == "update" })
  {
    Ok(def) ->
      case def.definition.parameters {
        [first, ..] -> function_parameter_name(first) == Ok("page_context")
        [] -> False
      }
    Error(Nil) -> False
  }
}

fn function_parameter_name(
  param: glance.FunctionParameter,
) -> Result(String, Nil) {
  case param {
    glance.FunctionParameter(label: Some(label), ..) -> Ok(label)
    glance.FunctionParameter(label: None, name: glance.Named(name), ..) ->
      Ok(name)
    _ -> Error(Nil)
  }
}

fn type_alias_targets_module(
  info: SourceModule,
  name: String,
  module_path: String,
) -> Bool {
  case
    list.find(info.ast.type_aliases, fn(def) { def.definition.name == name })
  {
    Ok(def) ->
      case
        glance_type_resolver.type_to_field_type(
          type_: def.definition.aliased,
          resolver: info.resolver,
          current_module: info.module_path,
          policy: glance_type_resolver.PreserveUnsupported,
        )
      {
        Ok(field_type.UserType(module_path: target, type_name:, args: [])) ->
          target == module_path && type_name == name
        _ -> False
      }
    Error(Nil) -> False
  }
}

fn load_result_constructor(
  custom_types: List(glance.Definition(glance.CustomType)),
) -> Result(String, String) {
  case
    custom_types
    |> list.find(fn(def) { def.definition.name == "LoadResult" })
    |> result.map(fn(def) { def.definition.variants })
  {
    Ok([variant]) -> Ok(variant.name)
    Ok(_) ->
      Error(
        "Rally can only generate load adapters for LoadResult types with one variant.",
      )
    Error(Nil) -> Error("Missing LoadResult type.")
  }
}

fn load_args(
  fields fields: List(glance.VariantField),
  resolver resolver: glance_type_resolver.TypeResolver,
  module_path module_path: String,
  variant_name variant_name: String,
) -> Result(List(LoadArg), String) {
  fields
  |> list.try_map(fn(field) {
    case field {
      glance.LabelledVariantField(label:, item:) -> {
        use type_ <- result.try(
          glance_type_resolver.type_to_field_type(
            type_: item,
            resolver:,
            current_module: module_path,
            policy: RejectUnsupported(module_path <> "." <> variant_name),
          )
          |> result.map_error(fn(_) {
            "Unsupported load argument type in "
            <> module_path
            <> "."
            <> variant_name
          }),
        )
        Ok(LoadArg(label:, type_ref: field_type.to_gleam_source(type_)))
      }
      glance.UnlabelledVariantField(_) ->
        Error(
          "Load constructor fields must be labelled in "
          <> module_path
          <> "."
          <> variant_name,
        )
    }
  })
}

fn validate_wire_boundary(
  ast ast: glance.Module,
  resolver resolver: TypeResolver,
  module_path module_path: String,
  wire_module wire_module: String,
  save_result_type save_result_type: Option(String),
  modules modules: List(SourceModule),
) -> Result(Nil, String) {
  let contract_types = case save_result_type {
    Some(save_type) -> ["ServerMsg", "LoadResult", save_type]
    None -> ["ServerMsg", "LoadResult"]
  }

  contract_types
  |> list.try_fold(Nil, fn(_, type_name) {
    validate_wire_custom_type(
      custom_types: ast.custom_types,
      imports: ast.imports,
      resolver:,
      module_path:,
      wire_module:,
      type_name:,
      modules:,
      seen: [],
    )
  })
}

fn validate_wire_custom_type(
  custom_types custom_types: List(glance.Definition(glance.CustomType)),
  imports imports: List(glance.Definition(glance.Import)),
  resolver resolver: TypeResolver,
  module_path module_path: String,
  wire_module wire_module: String,
  type_name type_name: String,
  modules modules: List(SourceModule),
  seen seen: List(#(String, String)),
) -> Result(Nil, String) {
  case list.find(custom_types, fn(def) { def.definition.name == type_name }) {
    Error(Nil) -> Ok(Nil)
    Ok(def) ->
      def.definition.variants
      |> list.try_fold(Nil, fn(_, variant) {
        validate_wire_variant(
          variant:,
          imports:,
          resolver:,
          module_path:,
          wire_module:,
          type_name:,
          modules:,
          seen: [#(wire_module, type_name), ..seen],
        )
      })
  }
}

fn validate_wire_variant(
  variant variant: glance.Variant,
  imports imports: List(glance.Definition(glance.Import)),
  resolver resolver: TypeResolver,
  module_path module_path: String,
  wire_module wire_module: String,
  type_name type_name: String,
  modules modules: List(SourceModule),
  seen seen: List(#(String, String)),
) -> Result(Nil, String) {
  variant.fields
  |> list.try_fold(Nil, fn(_, field) {
    validate_wire_variant_field(
      field:,
      imports:,
      resolver:,
      module_path:,
      wire_module:,
      type_name:,
      variant_name: variant.name,
      modules:,
      seen:,
    )
  })
}

fn validate_wire_variant_field(
  field field: glance.VariantField,
  imports imports: List(glance.Definition(glance.Import)),
  resolver resolver: TypeResolver,
  module_path module_path: String,
  wire_module wire_module: String,
  type_name type_name: String,
  variant_name variant_name: String,
  modules modules: List(SourceModule),
  seen seen: List(#(String, String)),
) -> Result(Nil, String) {
  case field {
    glance.LabelledVariantField(label:, item:) ->
      validate_wire_field_type(
        type_: item,
        imports:,
        field_path: type_name <> "." <> variant_name <> "." <> label,
        resolver:,
        module_path:,
        wire_module:,
        contract_name: type_name,
        modules:,
        seen:,
      )
    glance.UnlabelledVariantField(item:) ->
      validate_wire_field_type(
        type_: item,
        imports:,
        field_path: type_name <> "." <> variant_name <> ".field",
        resolver:,
        module_path:,
        wire_module:,
        contract_name: type_name,
        modules:,
        seen:,
      )
  }
}

fn validate_wire_field_type(
  type_ type_: glance.Type,
  imports imports: List(glance.Definition(glance.Import)),
  field_path field_path: String,
  resolver resolver: TypeResolver,
  module_path module_path: String,
  wire_module wire_module: String,
  contract_name contract_name: String,
  modules modules: List(SourceModule),
  seen seen: List(#(String, String)),
) -> Result(Nil, String) {
  use _ <- result.try(validate_shared_wire_imports(
    type_:,
    imports:,
    wire_module:,
    contract_name:,
    field_path:,
  ))

  use resolved <- result.try(
    glance_type_resolver.type_to_field_type(
      type_:,
      resolver:,
      current_module: wire_module,
      policy: RejectUnsupported(wire_module <> "." <> field_path),
    )
    |> result.map_error(fn(_) {
      "Unsupported wire contract type in " <> wire_module <> "." <> field_path
    }),
  )

  resolved
  |> field_type.collect_user_types
  |> list.unique
  |> list.try_fold(Nil, fn(_, ref) {
    let #(ref_module, ref_type_name) = ref
    case allowed_wire_reference(ref_module, module_path, wire_module) {
      True ->
        validate_referenced_wire_type(
          ref_module:,
          ref_type_name:,
          reference_path: field_path
            <> " -> "
            <> ref_module
            <> "."
            <> ref_type_name,
          module_path:,
          wire_module:,
          contract_name:,
          modules:,
          seen:,
        )
      False ->
        Error(
          "Invalid wire boundary in "
          <> wire_module
          <> "."
          <> contract_name
          <> ": "
          <> field_path
          <> " references "
          <> ref_module
          <> "."
          <> ref_type_name
          <> ". Rally wire contracts may reference page-local types, src/wire/**, broadcasts.gleam, primitives, and containers.",
        )
    }
  })
}

fn validate_referenced_wire_type(
  ref_module ref_module: String,
  ref_type_name ref_type_name: String,
  reference_path reference_path: String,
  module_path module_path: String,
  wire_module wire_module: String,
  contract_name contract_name: String,
  modules modules: List(SourceModule),
  seen seen: List(#(String, String)),
) -> Result(Nil, String) {
  use <- bool.guard(
    when: list.contains(seen, #(ref_module, ref_type_name)),
    return: Ok(Nil),
  )
  case find_source_module(modules, ref_module) {
    Error(Nil) -> Ok(Nil)
    Ok(info) ->
      case find_custom_type(info.ast.custom_types, ref_type_name) {
        Error(Nil) -> Ok(Nil)
        Ok(def) ->
          def.definition.variants
          |> list.try_fold(Nil, fn(_, variant) {
            variant.fields
            |> list.try_fold(Nil, fn(_, field) {
              let #(field_label, field_type) =
                variant_field_label_and_type(field)
              validate_wire_field_type(
                type_: field_type,
                imports: info.ast.imports,
                field_path: reference_path
                  <> "."
                  <> variant.name
                  <> "."
                  <> field_label,
                resolver: info.resolver,
                module_path:,
                wire_module:,
                contract_name:,
                modules:,
                seen: [#(ref_module, ref_type_name), ..seen],
              )
            })
          })
      }
  }
}

fn variant_field_label_and_type(
  field: glance.VariantField,
) -> #(String, glance.Type) {
  case field {
    glance.LabelledVariantField(label:, item:) -> #(label, item)
    glance.UnlabelledVariantField(item:) -> #("field", item)
  }
}

fn validate_shared_wire_imports(
  type_ type_: glance.Type,
  imports imports: List(glance.Definition(glance.Import)),
  wire_module wire_module: String,
  contract_name contract_name: String,
  field_path field_path: String,
) -> Result(Nil, String) {
  case find_targeted_import_use(type_, imports) {
    Error(Nil) -> Ok(Nil)
    Ok(TargetedImportUse(module_path:, target:, type_name:)) ->
      Error(
        "Invalid wire import in "
        <> wire_module
        <> "."
        <> contract_name
        <> ": "
        <> field_path
        <> " references "
        <> module_path
        <> "."
        <> type_name
        <> " through @target("
        <> target
        <> ") import "
        <> module_path
        <> ". Wire contracts are shared by Erlang and JavaScript, so wire-visible types must come from shared imports.",
      )
  }
}

fn find_targeted_import_use(
  type_ type_: glance.Type,
  imports imports: List(glance.Definition(glance.Import)),
) -> Result(TargetedImportUse, Nil) {
  case type_ {
    glance.NamedType(name:, module:, parameters:, ..) -> {
      case targeted_import_for_type(name, module, imports) {
        Ok(use_) -> Ok(use_)
        Error(Nil) -> find_targeted_import_use_in_types(parameters, imports)
      }
    }
    glance.TupleType(elements:, ..) ->
      find_targeted_import_use_in_types(elements, imports)
    glance.FunctionType(parameters:, return:, ..) ->
      find_targeted_import_use_in_types(
        list.append(parameters, [return]),
        imports,
      )
    glance.VariableType(..) | glance.HoleType(..) -> Error(Nil)
  }
}

fn find_targeted_import_use_in_types(
  types types: List(glance.Type),
  imports imports: List(glance.Definition(glance.Import)),
) -> Result(TargetedImportUse, Nil) {
  list.find_map(types, fn(type_) { find_targeted_import_use(type_, imports) })
}

fn targeted_import_for_type(
  type_name type_name: String,
  module_alias module_alias: Option(String),
  imports imports: List(glance.Definition(glance.Import)),
) -> Result(TargetedImportUse, Nil) {
  imports
  |> list.find_map(fn(def) {
    use target <- result.try(target_attribute(def.attributes))
    case targeted_import_matches_type(type_name, module_alias, def.definition) {
      True ->
        Ok(TargetedImportUse(
          module_path: def.definition.module,
          target:,
          type_name: imported_type_name(type_name, module_alias, def.definition),
        ))
      False -> Error(Nil)
    }
  })
}

fn targeted_import_matches_type(
  type_name type_name: String,
  module_alias module_alias: Option(String),
  import_ import_: glance.Import,
) -> Bool {
  case module_alias {
    Some(alias) -> import_alias(import_) == alias
    None ->
      list.any(import_.unqualified_types, fn(unqualified) {
        case unqualified.alias {
          Some(alias) -> alias == type_name
          None -> unqualified.name == type_name
        }
      })
  }
}

fn imported_type_name(
  type_name type_name: String,
  module_alias module_alias: Option(String),
  import_ import_: glance.Import,
) -> String {
  case module_alias {
    Some(_) -> type_name
    None ->
      import_.unqualified_types
      |> list.find_map(fn(unqualified) {
        case unqualified.alias {
          Some(alias) if alias == type_name -> Ok(unqualified.name)
          None if unqualified.name == type_name -> Ok(unqualified.name)
          _ -> Error(Nil)
        }
      })
      |> result.unwrap(type_name)
  }
}

fn import_alias(import_: glance.Import) -> String {
  case import_.alias {
    Some(glance.Named(name)) -> name
    Some(glance.Discarded(name)) -> name
    None ->
      import_.module
      |> string.split("/")
      |> list.last
      |> result.unwrap(import_.module)
  }
}

fn target_attribute(attributes: List(glance.Attribute)) -> Result(String, Nil) {
  attributes
  |> list.find_map(fn(attribute) {
    case attribute {
      glance.Attribute(name: "target", arguments: [glance.Variable(name:, ..)]) ->
        Ok(name)
      glance.Attribute(name: "target", arguments: [glance.String(value:, ..)]) ->
        Ok(value)
      _ -> Error(Nil)
    }
  })
}

fn find_source_module(
  modules: List(SourceModule),
  module_path: String,
) -> Result(SourceModule, Nil) {
  list.find(modules, fn(info) { info.source_module == module_path })
}

fn find_custom_type(
  custom_types: List(glance.Definition(glance.CustomType)),
  type_name: String,
) -> Result(glance.Definition(glance.CustomType), Nil) {
  list.find(custom_types, fn(def) { def.definition.name == type_name })
}

fn allowed_wire_reference(
  ref_module ref_module: String,
  module_path module_path: String,
  wire_module wire_module: String,
) -> Bool {
  ref_module == wire_module
  || ref_module == module_path
  || string.starts_with(ref_module, wire_module <> "/")
  || string.starts_with(ref_module, module_path <> "/")
  || ref_module == "broadcasts"
  || string.starts_with(ref_module, "wire/")
}

fn walk_directory(path path: String) -> Result(List(String), String) {
  use entries <- result.try(
    simplifile.read_directory(path)
    |> result.map_error(fn(e) {
      "Failed to read directory "
      <> path
      <> ": "
      <> simplifile.describe_error(e)
    }),
  )
  entries
  |> list.sort(string.compare)
  |> list.try_fold([], fn(acc, entry) {
    let child = path <> "/" <> entry
    let is_dir = simplifile.is_directory(child) |> result.unwrap(False)
    case is_dir {
      True -> {
        use <- bool.guard(when: entry == "generated", return: Ok(acc))
        use nested <- result.try(walk_directory(path: child))
        Ok(list.append(acc, nested))
      }
      False -> {
        case string.ends_with(child, ".gleam") {
          True -> Ok(list.append(acc, [child]))
          False -> Ok(acc)
        }
      }
    }
  })
}

fn module_from_path(src_root: String, path: String) -> String {
  let prefix = src_root <> "/"
  path
  |> string.drop_start(string.length(prefix))
  |> string.drop_end(string.length(".gleam"))
}

fn wire_imports(
  loads: List(LoadRpc),
  target: String,
  client_only client_only: Bool,
) -> String {
  loads
  |> list.filter(fn(load) { !client_only || load.import_on_client })
  |> list.map(fn(load) {
    target <> "\nimport " <> load.wire_module <> " as " <> wire_alias(load)
  })
  |> list.unique
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn server_ws_page_imports(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  loads
  |> list.filter(fn(load) {
    server_ws_direct_load(load, load_context:)
    || server_ws_direct_save(load, load_context:)
  })
  |> list.filter(fn(load) { load.module_path != load.wire_module })
  |> list.map(fn(load) {
    "@target(erlang)\nimport " <> load.module_path <> " as " <> page_alias(load)
  })
  |> list.unique
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn server_ws_direct_load(
  _load: LoadRpc,
  load_context load_context: Option(LoadContext),
) -> Bool {
  option.is_some(load_context)
}

fn server_ws_direct_save(
  load: LoadRpc,
  load_context load_context: Option(LoadContext),
) -> Bool {
  option.is_some(load_context) && option.is_some(load.save_result_type)
}

fn server_ws_has_direct_loads(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> Bool {
  list.any(loads, fn(load) {
    server_ws_direct_load(load, load_context:)
    || server_ws_direct_save(load, load_context:)
  })
}

fn server_ws_has_direct_page_loads(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> Bool {
  list.any(loads, fn(load) { server_ws_direct_load(load, load_context:) })
}

fn server_ws_load_context_import(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ws_has_direct_loads(loads, load_context:) {
    True -> load_context_import(load_context, "@target(erlang)")
    False -> ""
  }
}

fn server_ws_map_page_load_result(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ws_has_direct_page_loads(loads, load_context:) {
    True ->
      "
@target(erlang)
fn map_page_load_result(
  result: Result(a, List(String)),
) -> Result(a, List(LoadError)) {
  case result {
    Ok(value) -> Ok(value)
    Error(errors) ->
      Error(list.map(errors, fn(message) { LoadError(message:) }))
  }
}
"
    False -> ""
  }
}

fn server_ws_transport_loop(load_context: Option(LoadContext)) -> String {
  case load_context {
    Some(load_context) -> {
      let load_context_type = load_context_type_ref(load_context)
      "
@target(erlang)
pub type ConnectionState(admin_auth) {
  ConnectionState(
    load_context: " <> load_context_type <> ",
    admin_auth: Option(admin_auth),
    topics: List(String),
  )
}

@target(erlang)
pub fn on_init(
  load_context load_context: " <> load_context_type <> ",
  admin_auth admin_auth: Option(admin_auth),
) -> #(ConnectionState(admin_auth), Option(Selector(BitArray))) {
  topics.start()
  #(
    ConnectionState(load_context:, admin_auth:, topics: []),
    Some(topics.frame_selector()),
  )
}

@target(erlang)
pub fn on_close(state: ConnectionState(admin_auth)) -> Nil {
  state.topics
  |> list.each(topics.leave)
}

@target(erlang)
pub fn handler(
  state state: ConnectionState(admin_auth),
  msg msg: WebsocketMessage(BitArray),
  conn conn: WebsocketConnection,
) -> Next(ConnectionState(admin_auth), BitArray) {
  let handlers =
    Handlers(
      load_context: fn(state: ConnectionState(admin_auth)) {
        state.load_context
      },
      admin_auth: fn(state: ConnectionState(admin_auth)) { state.admin_auth },
    )

  case msg {
    mist.Binary(data) -> {
      handle_client_frame(
        state: state,
        conn: conn,
        data: data,
        handlers: handlers,
      )
      mist.continue(state)
    }
    mist.Custom(frame) -> {
      let _sent = mist.send_binary_frame(conn, frame)
      mist.continue(state)
    }
    mist.Text(frame) -> {
      case sync_topic_frame(state.topics, frame) {
        Ok(next_topics) ->
          mist.continue(ConnectionState(..state, topics: next_topics))
        Error(Nil) -> mist.continue(state)
      }
    }
    mist.Closed -> mist.stop()
    mist.Shutdown -> mist.stop()
  }
}
"
    }
    None -> ""
  }
}

fn server_ws_handlers_type_definition(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  "Handlers(" <> server_ws_handlers_type_params(loads, load_context:) <> ")"
}

fn server_ws_handlers_type(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  "Handlers(" <> server_ws_handlers_type_params(loads, load_context:) <> ")"
}

fn server_ws_handlers_type_params(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let auth_params =
    server_ws_authorized_mounts(loads, load_context:)
    |> list.map(fn(mount) { mount <> "_auth" })

  ["state", ..auth_params]
  |> string.join(", ")
}

fn load_context_import(
  load_context: Option(LoadContext),
  target: String,
) -> String {
  case load_context {
    Some(LoadContext(module_path:, type_name: _)) ->
      target <> "\nimport " <> module_path <> " as load_context\n"
    None -> ""
  }
}

fn load_context_type_ref(load_context: LoadContext) -> String {
  let LoadContext(module_path: _, type_name:) = load_context
  "load_context." <> type_name
}

fn push_import(push_contract: Option(PushContract), target: String) -> String {
  case push_contract {
    Some(PushContract(module_path:, type_name: _)) ->
      target <> "\nimport " <> module_path <> " as push_payload\n"
    None -> ""
  }
}

fn push_type_ref(push_contract: PushContract) -> String {
  let PushContract(module_path: _, type_name:) = push_contract
  "push_payload." <> type_name
}

fn client_server_frame_type(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(contract) -> "@target(javascript)
pub type ServerFrame {
  Push(module: String, message: " <> push_type_ref(contract) <> ")
}
"
    None ->
      "@target(javascript)
pub type ServerFrame {
  UnsupportedPushFrame
}
"
  }
}

fn client_decode_server_frame(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(_) ->
      "@target(javascript)
pub fn decode_server_frame(bytes: BitArray) -> Result(ServerFrame, Nil) {
  case bytes {
    <<1, payload:bits>> -> {
      case decode_any(payload) {
        Ok(#(module, message)) -> Ok(Push(module:, message:))
        Error(Nil) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}
"
    None ->
      "@target(javascript)
pub fn decode_server_frame(_bytes: BitArray) -> Result(ServerFrame, Nil) {
  Error(Nil)
}
"
  }
}

fn server_protocol_push_helpers(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(contract) -> {
      let PushContract(module_path:, type_name:) = contract
      "@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"" <> wire_encoder_function(
        module_path,
        type_name,
      ) <> "\")
fn encode_push_payload(_message: " <> push_type_ref(contract) <> ") -> a {
  panic as \"generated/rally/server_protocol.encode_push_payload external missing\"
}

@target(erlang)
pub fn encode_push(
  module module: String,
  message message: " <> push_type_ref(contract) <> ",
) -> BitArray {
  let payload = encode_any(#(module, encode_push_payload(message)))
  <<1, payload:bits>>
}
"
    }
    None -> ""
  }
}

fn server_ws_push_frame(push_contract: Option(PushContract)) -> String {
  case push_contract {
    Some(contract) -> "
@target(erlang)
pub fn push_frame(
  module module: String,
  message message: " <> push_type_ref(contract) <> ",
) -> BitArray {
  server_protocol.encode_push(module, message)
}
"
    None -> ""
  }
}

fn server_ws_sync_topic_frame() -> String {
  "
@target(erlang)
pub fn sync_topic_frame(
  current current: List(String),
  frame frame: String,
) -> Result(List(String), Nil) {
  let prefix = \"sub:\"
  case frame {
    \"unsub\" -> {
      current
      |> list.each(topics.leave)
      Ok([])
    }
    _ -> case string.starts_with(frame, prefix) {
      False -> Error(Nil)
      True -> {
      let next =
        frame
        |> string.drop_start(string.length(prefix))
        |> string.split(\",\")
        |> list.filter(fn(topic) { topic != \"\" })

      current
      |> list.filter(fn(topic) { !list.contains(next, topic) })
      |> list.each(topics.leave)
      next
      |> list.filter(fn(topic) { !list.contains(current, topic) })
      |> list.each(topics.join)
      Ok(next)
      }
    }
  }
}
"
}

fn wire_alias(load: LoadRpc) -> String {
  load.name <> "_wire"
}

fn page_alias(load: LoadRpc) -> String {
  case load.module_path == load.wire_module {
    True -> wire_alias(load)
    False -> load.name <> "_page"
  }
}

fn pascal_name(load: LoadRpc) -> String {
  load.name
  |> string.split("_")
  |> list.map(fn(word) {
    case string.pop_grapheme(word) {
      Ok(#(first, rest)) -> string.uppercase(first) <> rest
      Error(Nil) -> word
    }
  })
  |> string.join("")
}

fn arg_signature(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) {
    "\n  " <> arg.label <> " " <> arg.label <> ": " <> arg.type_ref <> ","
  })
  |> string.join("")
}

fn arg_labels(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { arg.label <> ":" })
  |> string.join(", ")
}

fn call_args(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { arg.label })
  |> string.join(", ")
}

fn constructor(load: LoadRpc) -> String {
  case load.import_on_client, load.args {
    False, _ -> "message"
    True, [] -> wire_alias(load) <> "." <> load.request_constructor
    True, args ->
      wire_alias(load)
      <> "."
      <> load.request_constructor
      <> "("
      <> arg_labels(args)
      <> ")"
  }
}

fn client_encode_request(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }

  "@target(javascript)
pub fn encode_" <> load.name <> "_request(
  request_id request_id: Int," <> signature <> "
) -> BitArray {
  encode_any(#(
    request_id,
    \"" <> load.module_path <> "\",
    " <> constructor(load) <> ",
  ))
}
"
}

fn client_decode_load_result(load: LoadRpc) -> String {
  "@target(javascript)
pub fn decode_" <> load.name <> "_load_result(
  bytes: BitArray,
) -> Result(
  #(Int, Result(" <> client_load_result_type(load) <> ", List(ApiLoadError))),
  Nil,
) {
  decode_result_envelope(bytes)
}
"
}

fn client_decode_save_result(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn decode_" <> load.name <> "_save_result(
  bytes: BitArray,
) -> Result(#(Int, Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))), Nil) {
  decode_result_envelope(bytes)
}
")
  }
}

fn server_request_type(load: LoadRpc) -> String {
  "@target(erlang)
pub type " <> pascal_name(load) <> "ClientRequest {
  " <> pascal_name(load) <> "ClientRequest(
    request_id: Int,
    module: String,
    message: " <> wire_alias(load) <> ".ServerMsg,
  )
}
"
}

fn server_decode_request(load: LoadRpc) -> String {
  "@target(erlang)
pub fn decode_" <> load.name <> "_request(
  bytes: BitArray,
) -> Result(" <> pascal_name(load) <> "ClientRequest, Nil) {
  case decode_any(bytes) {
    Ok(#(request_id, module, message)) ->
      Ok(" <> pascal_name(load) <> "ClientRequest(request_id:, module:, message:))
    _ -> Error(Nil)
  }
}
"
}

fn server_encode_load_result(load: LoadRpc) -> String {
  "@target(erlang)
pub fn encode_" <> load.name <> "_load_result(
  request_id request_id: Int,
  result result: Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
) -> BitArray {
  encode_result_frame(request_id, encode_" <> load.name <> "_load_result_payload(result))
}
"
}

fn server_encode_save_result(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) -> Some("@target(erlang)
pub fn encode_" <> load.name <> "_save_result(
  request_id request_id: Int,
  result result: Result(" <> wire_alias(load) <> "." <> save_result_type <> ", List(ApiSaveError)),
) -> BitArray {
  encode_result_frame(request_id, encode_" <> load.name <> "_save_result_payload(result))
}
")
  }
}

fn server_load_result_encoder(load: LoadRpc) -> String {
  "@target(erlang)
fn encode_" <> load.name <> "_load_result_payload(
  result: Result(" <> wire_alias(load) <> ".LoadResult, List(ApiLoadError)),
) -> Result(a, List(ApiLoadError)) {
  encode_ok_payload(result, encode_" <> load.name <> "_load_result_value)
}

@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"" <> wire_encoder_function(
    load.wire_module,
    "LoadResult",
  ) <> "\")
fn encode_" <> load.name <> "_load_result_value(
  _value: " <> wire_alias(load) <> ".LoadResult,
) -> a {
  panic as \"generated/rally/server_protocol.encode_" <> load.name <> "_load_result_value external missing\"
}
"
}

fn server_save_result_encoder(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) -> Some("@target(erlang)
fn encode_" <> load.name <> "_save_result_payload(
  result: Result(" <> wire_alias(load) <> "." <> save_result_type <> ", List(ApiSaveError)),
) -> Result(a, List(ApiSaveError)) {
  encode_ok_payload(result, encode_" <> load.name <> "_save_result_value)
}

@target(erlang)
@external(erlang, \"generated@rpc_wire\", \"" <> wire_encoder_function(
        load.wire_module,
        save_result_type,
      ) <> "\")
fn encode_" <> load.name <> "_save_result_value(
  _value: " <> wire_alias(load) <> "." <> save_result_type <> ",
) -> a {
  panic as \"generated/rally/server_protocol.encode_" <> load.name <> "_save_result_value external missing\"
}
")
  }
}

fn transport_send_load(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }
  let call_args = case load.import_on_client, load.args {
    False, _ -> ", message"
    True, [] -> ""
    True, args -> ", " <> call_args(args)
  }

  "@target(javascript)
pub fn send_" <> load.name <> "_load(" <> signature <> "
  on_result on_result: fn(
    Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)),
  ) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_" <> load.name <> "_request(request_id" <> call_args <> ")
    send_" <> load.name <> "_load_frame(request_id, frame, on_result, dispatch)
  })
}
"
}

fn transport_send_save(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn send_" <> load.name <> "_save(
  message message: a,
  on_result on_result: fn(Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    let request_id = next_request_id()
    let frame = client_protocol.encode_" <> load.name <> "_request(request_id, message)
    send_" <> load.name <> "_save_frame(request_id, frame, on_result, dispatch)
  })
}
")
  }
}

fn transport_external(load: LoadRpc) -> String {
  "@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_load_frame\")
fn send_" <> load.name <> "_load_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(" <> client_load_result_type(load) <> ", List(ApiLoadError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
"
}

fn transport_save_external(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
@external(javascript, \"./client_transport_ffi.mjs\", \"send_save_frame\")
fn send_" <> load.name <> "_save_frame(
  _request_id: Int,
  _frame: BitArray,
  _on_result: fn(Result(" <> client_save_result_type(load) <> ", List(ApiSaveError))) -> msg,
  _dispatch: fn(msg) -> Nil,
) -> Nil {
  Nil
}
")
  }
}

fn page_server_load(load: LoadRpc) -> String {
  let signature = case load.import_on_client {
    True -> arg_signature(load.args)
    False -> "\n  message message: a,"
  }
  let call_args = case load.import_on_client, load.args {
    False, _ -> "message: message, "
    True, [] -> ""
    True, args -> arg_labels(args) <> ", "
  }

  "@target(javascript)
pub fn load_" <> load.name <> "(" <> signature <> "
  on_result on_result: fn(
    Result(" <> client_load_result_type(load) <> ", List(LoadError)),
  ) -> msg,
) -> Effect(msg) {
  client_transport.send_" <> load.name <> "_load(
    " <> call_args <> "on_result: fn(result) {
      on_result(map_load_result(result))
    },
  )
}
"
}

fn page_server_save(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(javascript)
pub fn save_" <> load.name <> "(
  message message: a,
  on_result on_result: fn(Result(" <> client_save_result_type(load) <> ", List(SaveError))) -> msg,
) -> Effect(msg) {
  client_transport.send_" <> load.name <> "_save(
    message: message,
    on_result: fn(result) {
      on_result(map_save_result(result))
    },
  )
}
")
  }
}

fn server_ws_handler_fields(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let load_context_fields = case
    server_ws_has_direct_loads(loads, load_context:),
    load_context
  {
    True, Some(context) -> [
      "    load_context: fn(state) -> " <> load_context_type_ref(context) <> ",",
    ]
    _, _ -> []
  }
  let authorization_fields =
    server_ws_authorized_mounts(loads, load_context:)
    |> list.map(fn(mount) {
      "    " <> mount <> "_auth: fn(state) -> Option(" <> mount <> "_auth),"
    })
  let load_fields =
    loads
    |> list.filter(fn(load) { !server_ws_direct_load(load, load_context:) })
    |> list.map(server_ws_load_handler_field)
  let save_fields =
    loads
    |> list.filter(fn(load) { !server_ws_direct_save(load, load_context:) })
    |> list.map(server_ws_save_handler_fields)
    |> option.values

  list.append(
    load_context_fields,
    list.append(authorization_fields, list.append(load_fields, save_fields)),
  )
  |> string.join("\n")
}

fn server_ws_authorized_mounts(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> List(String) {
  loads
  |> list.filter(fn(load) {
    load_mount(load) != "public"
    && {
      server_ws_direct_load(load, load_context:)
      || server_ws_direct_save(load, load_context:)
    }
  })
  |> list.map(load_mount)
  |> list.unique
}

fn server_ws_load_handler_field(load: LoadRpc) -> String {
  "    "
  <> load.name
  <> "_load: fn("
  <> server_ws_handler_args_type(load)
  <> ") -> Result("
  <> wire_alias(load)
  <> ".LoadResult, List(LoadError)),"
}

fn server_ws_save_handler_fields(load: LoadRpc) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(save_result_type) ->
      Some(
        "    "
        <> load.name
        <> "_save: fn(state, "
        <> wire_alias(load)
        <> ".ServerMsg) -> Result("
        <> wire_alias(load)
        <> "."
        <> save_result_type
        <> ", List(SaveError)),\n"
        <> "    after_"
        <> load.name
        <> "_save: fn(state, "
        <> wire_alias(load)
        <> ".ServerMsg, "
        <> wire_alias(load)
        <> "."
        <> save_result_type
        <> ") -> Nil,",
      )
  }
}

fn server_ws_dispatch_cases(loads: List(LoadRpc)) -> String {
  case loads {
    [] -> "Nil"
    [first, ..rest] -> server_ws_dispatch_case(first, rest)
  }
}

fn server_ws_dispatch_case(load: LoadRpc, rest: List(LoadRpc)) -> String {
  "case try_"
  <> load.name
  <> "_request(state: state, conn: conn, data: data, handlers: handlers) {
    Ok(Nil) -> Nil
    Error(Nil) -> "
  <> server_ws_dispatch_cases(rest)
  <> "
  }"
}

fn server_ws_try_request(
  load: LoadRpc,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  "@target(erlang)
fn try_" <> load.name <> "_request(
  state state: state,
  conn conn: WebsocketConnection,
  data data: BitArray,
  handlers handlers: " <> server_ws_handlers_type(loads, load_context:) <> ",
) -> Result(Nil, Nil) {
  case server_protocol.decode_" <> load.name <> "_request(data) {
    Ok(server_protocol." <> pascal_name(load) <> "ClientRequest(
      request_id: request_id,
      module: \"" <> load.module_path <> "\",
      message: " <> server_ws_load_pattern(load) <> ",
    )) -> {
      send_" <> load.name <> "_load_result(
        state: state,
        conn: conn,
        request_id: request_id,
        handlers: handlers" <> server_ws_pass_args(load.args) <> ",
      )
      Ok(Nil)
    }
" <> server_ws_try_save_case(load) <> "
    _ -> Error(Nil)
  }
}
"
}

fn server_ws_try_save_case(load: LoadRpc) -> String {
  case load.save_result_type {
    None -> ""
    Some(_) -> "    Ok(server_protocol." <> pascal_name(load) <> "ClientRequest(
      request_id: request_id,
      module: \"" <> load.module_path <> "\",
      message: message,
    )) ->
      case message {
" <> server_ws_module_load_patterns(load) <> "        _ -> {
          send_" <> load.name <> "_save_result(
            state: state,
            conn: conn,
            request_id: request_id,
            message: message,
            handlers: handlers,
          )
          Ok(Nil)
        }
      }
"
  }
}

fn server_ws_send_load_result(
  load: LoadRpc,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  "@target(erlang)
fn send_" <> load.name <> "_load_result(
  state state: state,
  conn conn: WebsocketConnection,
  request_id request_id: Int,
  handlers handlers: " <> server_ws_handlers_type(loads, load_context:) <> server_ws_arg_params(
    load.args,
  ) <> ",
) -> Nil {
  let result =
    " <> server_ws_load_result_call(load, load_context:) <> "
    |> map_load_result

  let _sent =
    mist.send_binary_frame(
      conn,
      server_protocol.encode_" <> load.name <> "_load_result(
        request_id: request_id,
        result: result,
      ),
    )
  Nil
}
  "
}

fn server_ws_load_result_call(
  load: LoadRpc,
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ws_direct_load(load, load_context:) {
    True ->
      server_ws_authorized_result(
        load:,
        error: "Error([LoadError(message: \"Unauthorized.\")])",
        body: generated_direct_load_call(
          load:,
          load_context: "handlers.load_context(state)",
          args: call_args(load.args),
        )
          <> "\n    |> map_page_load_result",
      )
    False ->
      "handlers."
      <> load.name
      <> "_load("
      <> server_ws_handler_args_call(load)
      <> ")"
  }
}

fn server_ws_authorized_result(
  load load: LoadRpc,
  error error: String,
  body body: String,
) -> String {
  case load_mount(load) {
    "public" -> body
    mount -> "case handlers." <> mount <> "_auth(state) {
      None -> " <> error <> "
      Some(_) -> " <> body <> "
    }"
  }
}

fn server_ws_send_save_result(
  load: LoadRpc,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
  push_contract push_contract: Option(PushContract),
) -> Option(String) {
  case load.save_result_type {
    None -> None
    Some(_) -> Some("@target(erlang)
fn send_" <> load.name <> "_save_result(
  state state: state,
  conn conn: WebsocketConnection,
  request_id request_id: Int,
  message message: " <> wire_alias(load) <> ".ServerMsg,
  handlers handlers: " <> server_ws_handlers_type(loads, load_context:) <> ",
) -> Nil {
  let result = " <> server_ws_save_result_call(load, load_context:) <> "

  let _sent =
    mist.send_binary_frame(
      conn,
      server_protocol.encode_" <> load.name <> "_save_result(
        request_id: request_id,
        result: map_save_result(result),
      ),
    )

  case result {
    Ok(value) -> " <> server_ws_after_save_call(
        load,
        load_context:,
        push_contract:,
      ) <> "
    Error(_) -> Nil
  }
}
")
  }
}

fn server_ws_save_result_call(
  load: LoadRpc,
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ws_direct_save(load, load_context:) {
    True ->
      server_ws_authorized_result(
        load:,
        error: "Error([SaveError(field: None, message: \"Unauthorized.\")])",
        body: "case "
          <> page_alias(load)
          <> ".handle(handlers.load_context(state), message) {
      Ok(value) -> Ok(value)
      Error("
          <> page_alias(load)
          <> ".SaveError(message: message)) ->
        Error([SaveError(field: None, message:)])
    }",
      )
    False -> "handlers." <> load.name <> "_save(state, message)"
  }
}

fn server_ws_after_save_call(
  load: LoadRpc,
  load_context load_context: Option(LoadContext),
  push_contract push_contract: Option(PushContract),
) -> String {
  case server_ws_direct_save(load, load_context:), push_contract {
    True, Some(_) ->
      "case "
      <> page_alias(load)
      <> ".after_save(handlers.load_context(state), value) {
      Ok(push_payload.TargetedEvent(topics: target_topics, event: event)) ->
        target_topics
        |> list.each(fn(topic) {
          let topic_name = push_payload.topic_name(topic)
          topics.broadcast_except_self(
            topic_name,
            push_frame(module: topic_name, message: event),
          )
        })
      Error(Nil) -> Nil
    }"
    True, None -> "Nil"
    False, _ -> "handlers.after_" <> load.name <> "_save(state, message, value)"
  }
}

fn server_ws_handler_args_type(load: LoadRpc) -> String {
  let arg_types =
    load.args
    |> list.map(fn(arg) { arg.type_ref })
    |> string.join(", ")

  case arg_types {
    "" -> "state"
    _ -> "state, " <> arg_types
  }
}

fn server_ws_handler_args_call(load: LoadRpc) -> String {
  let args = call_args(load.args)

  case args {
    "" -> "state"
    _ -> "state, " <> args
  }
}

fn server_ws_arg_params(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) {
    ",\n  " <> arg.label <> " " <> arg.label <> ": " <> arg.type_ref
  })
  |> string.join("")
}

fn server_ws_pass_args(args: List(LoadArg)) -> String {
  args
  |> list.map(fn(arg) { ",\n        " <> arg.label <> ": " <> arg.label })
  |> string.join("")
}

fn server_ws_load_pattern(load: LoadRpc) -> String {
  case load.args {
    [] -> wire_alias(load) <> "." <> load.request_constructor
    args ->
      wire_alias(load)
      <> "."
      <> load.request_constructor
      <> "("
      <> arg_labels(args)
      <> ")"
  }
}

fn server_ws_module_load_patterns(load: LoadRpc) -> String {
  "        " <> server_ws_load_pattern(load) <> " -> Error(Nil)\n"
}

fn load_mount(load: LoadRpc) -> String {
  load_mount_from_module(load.module_path)
}

fn load_mount_from_module(module_path: String) -> String {
  case string.split(module_path, "/") {
    [mount, ..] -> mount
    [] -> "app"
  }
}

fn load_mounts(loads: List(LoadRpc)) -> List(String) {
  loads
  |> list.map(load_mount)
  |> list.unique
}

fn mount_loads(loads: List(LoadRpc), mount: String) -> List(LoadRpc) {
  loads
  |> list.filter(fn(load) { load_mount(load) == mount })
}

fn mount_alias(mount: String, suffix: String) -> String {
  mount <> "_" <> suffix
}

fn mount_type_prefix(mount: String) -> String {
  mount
  |> string.split("_")
  |> list.map(fn(word) {
    case string.pop_grapheme(word) {
      Ok(#(first, rest)) -> string.uppercase(first) <> rest
      Error(Nil) -> word
    }
  })
  |> string.join("")
}

fn server_ssr_mount_imports(mounts: List(String)) -> String {
  mounts
  |> list.map(fn(mount) { "@target(erlang)
import generated/proute/" <> mount <> "/page_input as " <> mount_alias(
      mount,
      "page_input",
    ) <> "
@target(erlang)
import generated/proute/" <> mount <> "/pages as " <> mount_alias(
      mount,
      "pages",
    ) <> "
@target(erlang)
import generated/proute/" <> mount <> "/routes as " <> mount_alias(
      mount,
      "routes",
    ) })
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn server_ssr_direct_loads(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> List(LoadRpc) {
  loads
  |> list.filter(fn(load) { server_ssr_direct_load(load, load_context:) })
}

fn server_ssr_direct_load(
  load: LoadRpc,
  load_context load_context: Option(LoadContext),
) -> Bool {
  option.is_some(load_context) && server_ssr_supported_route_args(load)
}

fn server_ssr_supported_route_args(load: LoadRpc) -> Bool {
  let route_args = server_ssr_route_args(load)

  list.length(route_args) == list.length(load.args)
  && list.all(route_args, fn(pair) {
    let #(route_field, arg) = pair
    case arg.type_ref {
      "Int" -> True
      "String" -> route_field == arg.label
      _ -> False
    }
  })
}

fn server_ssr_has_direct_loads(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> Bool {
  list.any(loads, fn(load) { server_ssr_direct_load(load, load_context:) })
}

fn server_ssr_has_indirect_loads(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> Bool {
  list.any(loads, fn(load) { !server_ssr_direct_load(load, load_context:) })
}

fn server_ssr_mount_uses_direct_context(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> Bool {
  server_ssr_has_direct_loads(loads, load_context:)
  && !server_ssr_has_indirect_loads(loads, load_context:)
}

fn server_ssr_load_context_import(
  direct_loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  case direct_loads {
    [] -> ""
    _ -> load_context_import(load_context, "@target(erlang)")
  }
}

fn server_ssr_int_import(loads: List(LoadRpc)) -> String {
  case
    list.any(loads, fn(load) {
      list.any(load.args, fn(arg) { arg.type_ref == "Int" })
    })
  {
    True -> "@target(erlang)\nimport gleam/int\n"
    False -> ""
  }
}

fn server_ssr_page_imports(loads: List(LoadRpc)) -> String {
  loads
  |> list.filter(fn(load) { load.module_path != load.wire_module })
  |> list.map(fn(load) {
    "@target(erlang)\nimport " <> load.module_path <> " as " <> page_alias(load)
  })
  |> list.unique
  |> string.join("\n")
  |> fn(imports) {
    case imports {
      "" -> ""
      _ -> imports <> "\n"
    }
  }
}

fn server_ssr_mount_output_type(mount: String) -> String {
  let prefix = mount_type_prefix(mount)

  "@target(erlang)
pub type " <> prefix <> "SsrOutput {
  " <> prefix <> "SsrOutput(
    current_path: String,
    content: Element(Nil),
    hydration: List(String),
  )
}
"
}

fn server_ssr_mount_route_type(mount: String, loads: List(LoadRpc)) -> String {
  let prefix = mount_type_prefix(mount)
  let pages = mount_alias(mount, "pages")

  "@target(erlang)
pub type " <> prefix <> "LoadRoute {
  " <> prefix <> "NoLoad
" <> string.join(list.map(loads, fn(load) { "  " <> pascal_name(load) <> "Load(
    to_message: fn(Result(" <> wire_alias(load) <> ".LoadResult, List(String))) -> " <> pages <> ".Message,
  )" }), "\n") <> "
}
"
}

fn server_ssr_mount_handlers_type(
  mount: String,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let prefix = mount_type_prefix(mount)
  let routes = mount_alias(mount, "routes")
  case server_ssr_mount_uses_direct_context(loads, load_context:) {
    True -> ""
    False -> {
      let load_context_fields = case
        server_ssr_has_direct_loads(loads, load_context:),
        load_context
      {
        True, Some(context) -> [
          "    load_context: fn() -> " <> load_context_type_ref(context) <> ",",
        ]
        _, _ -> []
      }
      let load_fields =
        loads
        |> list.filter(fn(load) { !server_ssr_direct_load(load, load_context:) })
        |> list.map(fn(load) {
          "    "
          <> load.name
          <> "_load: fn("
          <> routes
          <> ".Route) -> Result("
          <> wire_alias(load)
          <> ".LoadResult, List(String)),"
        })

      "@target(erlang)
pub type " <> prefix <> "LoadHandlers {
  " <> prefix <> "LoadHandlers(
" <> string.join(list.append(load_context_fields, load_fields), "\n") <> "
  )
}
"
    }
  }
}

fn server_ssr_mount_render_path(
  mount: String,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let prefix = mount_type_prefix(mount)
  let page_input = mount_alias(mount, "page_input")
  let routes = mount_alias(mount, "routes")
  let pages = mount_alias(mount, "pages")

  "@target(erlang)
pub fn " <> mount <> "_render_path(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  path path: String,
  " <> server_ssr_mount_context_param(mount, loads, load_context:) <> "
) -> " <> prefix <> "SsrOutput {
  let route = " <> routes <> ".parse_path(path)
  let #(page, hydration) =
    " <> mount <> "_boot_page(
      page_context:,
      query_params:,
      route:,
      " <> server_ssr_mount_context_arg(loads, load_context:) <> "
      update_page: fn(page, message) {
        " <> server_ssr_mount_update_call(pages, loads) <> "
      },
    )

  " <> prefix <> "SsrOutput(
    current_path: " <> routes <> ".route_to_path(route),
    content: " <> pages <> ".view(page) |> element.map(fn(_) { Nil }),
    hydration:,
  )
}
"
}

fn server_ssr_mount_context_param(
  mount: String,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  case
    server_ssr_mount_uses_direct_context(loads, load_context:),
    load_context
  {
    True, Some(context) ->
      "load_context load_context: " <> load_context_type_ref(context) <> ","
    _, _ -> "handlers handlers: " <> mount_type_prefix(mount) <> "LoadHandlers,"
  }
}

fn server_ssr_mount_context_arg(
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ssr_mount_uses_direct_context(loads, load_context:) {
    True -> "load_context:,"
    False -> "handlers:,"
  }
}

fn server_ssr_mount_update_call(pages: String, loads: List(LoadRpc)) -> String {
  case mount_loads_update_uses_page_context(loads) {
    True -> pages <> ".update(page_context, page, message)"
    False -> pages <> ".update(page, message)"
  }
}

fn mount_loads_update_uses_page_context(loads: List(LoadRpc)) -> Bool {
  list.any(loads, fn(load) { load.update_uses_page_context })
}

fn server_ssr_mount_boot_page(
  mount: String,
  loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  let prefix = mount_type_prefix(mount)
  let page_input = mount_alias(mount, "page_input")
  let pages = mount_alias(mount, "pages")
  let routes = mount_alias(mount, "routes")

  "@target(erlang)
pub fn " <> mount <> "_boot_page(
  page_context page_context: PageContext,
  query_params query_params: " <> page_input <> ".QueryParams,
  route route: " <> routes <> ".Route,
  " <> server_ssr_mount_context_param(mount, loads, load_context:) <> "
  update_page update_page: fn(" <> pages <> ".Page, " <> pages <> ".Message) -> #(" <> pages <> ".Page, Effect(" <> pages <> ".Message)),
) -> #(" <> pages <> ".Page, List(String)) {
  let page = " <> pages <> ".load_sync(page_context, query_params, route)

  case " <> mount <> "_load_route(route) {
    " <> prefix <> "NoLoad -> #(page, [])
" <> string.join(
    list.map(loads, fn(load) {
      server_ssr_mount_boot_case(load, loads, load_context:)
    }),
    "\n",
  ) <> "
  }
}
"
}

fn server_ssr_mount_load_route_function(
  mount: String,
  loads: List(LoadRpc),
) -> String {
  let prefix = mount_type_prefix(mount)
  let routes = mount_alias(mount, "routes")

  "@target(erlang)
pub fn " <> mount <> "_load_route(route route: " <> routes <> ".Route) -> " <> prefix <> "LoadRoute {
  case route {
" <> string.join(list.flat_map(loads, server_ssr_load_route_cases), "\n") <> "
    _ -> " <> prefix <> "NoLoad
  }
}
"
}

fn server_ssr_load_route_cases(load: LoadRpc) -> List(String) {
  load.route_modules
  |> list.map(fn(route_module) {
    "    "
    <> server_ssr_route_module_pattern(route_module)
    <> " -> "
    <> pascal_name(load)
    <> "Load(to_message: fn(result) { "
    <> server_ssr_load_result_message(load, route_module)
    <> " })"
  })
}

fn server_ssr_load_result_message(
  load: LoadRpc,
  route_module: String,
) -> String {
  let pages = mount_alias(load_mount(load), "pages")
  pages
  <> "."
  <> route_message_constructor(route_module)
  <> "("
  <> page_alias(load)
  <> ".loaded_from_wire(result))"
}

fn server_ssr_route_module_pattern(route_module: String) -> String {
  let mount = load_mount_from_module(route_module)
  mount_alias(mount, "routes")
  <> "."
  <> route_constructor_for_module(route_module)
  <> server_ssr_route_module_pattern_args(route_module)
}

fn server_ssr_route_module_pattern_args(route_module: String) -> String {
  route_module
  |> dynamic_segments_from_module
  |> list.map(fn(segment) { segment <> ": _" })
  |> fn(args) {
    case args {
      [] -> ""
      _ -> "(" <> string.join(args, ", ") <> ")"
    }
  }
}

fn server_ssr_mount_boot_case(
  load: LoadRpc,
  mount_loads mount_loads: List(LoadRpc),
  load_context load_context: Option(LoadContext),
) -> String {
  "    " <> pascal_name(load) <> "Load(to_message:) -> {
      let result = " <> server_ssr_load_result_call(
    load,
    direct_context: server_ssr_mount_uses_direct_context(
      mount_loads,
      load_context:,
    ),
    load_context:,
  ) <> "
      boot_loaded_page(
        page: page,
        result: result,
        hydration_payload: " <> load.name <> "_hydration_payload,
        to_message: to_message,
        update_page: update_page,
      )
    }"
}

fn server_ssr_load_result_call(
  load: LoadRpc,
  direct_context direct_context: Bool,
  load_context load_context: Option(LoadContext),
) -> String {
  case server_ssr_direct_load(load, load_context:) {
    True -> server_ssr_page_load_call(load, direct_context:)
    False -> "handlers." <> load.name <> "_load(route)"
  }
}

fn server_ssr_page_load_call(
  load: LoadRpc,
  direct_context direct_context: Bool,
) -> String {
  let context = case direct_context {
    True -> "load_context"
    False -> "handlers.load_context()"
  }

  case load.args {
    [] -> generated_direct_load_call(load:, load_context: context, args: "")
    _ -> "case route {
        " <> server_ssr_route_pattern(load) <> " -> " <> server_ssr_page_load_arg_body(
        load,
        load_context: context,
      ) <> "
        _ -> Error([\"Unexpected route.\"])
      }"
  }
}

fn server_ssr_page_load_arg_body(
  load: LoadRpc,
  load_context load_context: String,
) -> String {
  let args = server_ssr_route_args(load)
  let route_fields = list.map(args, fn(pair) { pair.0 })
  let load_args = list.map(args, fn(pair) { pair.1 })

  case list.any(load_args, fn(arg) { arg.type_ref == "Int" }) {
    False ->
      generated_direct_load_call(
        load:,
        load_context:,
        args: call_args(load.args),
      )
    True ->
      server_ssr_int_load_arg_body(load, route_fields, load_args, load_context:)
  }
}

fn server_ssr_int_load_arg_body(
  load: LoadRpc,
  route_fields: List(String),
  load_args: List(LoadArg),
  load_context load_context: String,
) -> String {
  let parsers =
    list.zip(route_fields, load_args)
    |> list.map(fn(pair) {
      let #(route_field, arg) = pair
      case arg.type_ref {
        "Int" -> Some("case int.parse(" <> route_field <> ") {
            Ok(" <> arg.label <> ") -> ")
        _ -> None
      }
    })
    |> option.values

  let close_parens =
    list.repeat("}", list.length(parsers))
    |> string.join("\n")

  string.join(parsers, "")
  <> generated_direct_load_call(
    load:,
    load_context:,
    args: call_args(load.args),
  )
  <> "
            Error(Nil) -> Error([\"Invalid route parameter.\"])
          "
  <> close_parens
}

fn generated_direct_load_call(
  load load: LoadRpc,
  load_context load_context: String,
  args args: String,
) -> String {
  "case "
  <> page_alias(load)
  <> ".load("
  <> call_args_with_context(load_context, args)
  <> ") {
      Ok(data) -> Ok("
  <> wire_alias(load)
  <> "."
  <> load.load_result_constructor
  <> "(data))
      Error("
  <> page_alias(load)
  <> ".LoadError(message: message)) -> Error([message])
    }"
}

fn call_args_with_context(load_context: String, args: String) -> String {
  case args {
    "" -> load_context
    _ -> load_context <> ", " <> args
  }
}

fn server_ssr_route_pattern(load: LoadRpc) -> String {
  mount_alias(load_mount(load), "routes")
  <> "."
  <> server_ssr_route_constructor(load)
  <> server_ssr_route_pattern_args(load)
}

fn server_ssr_route_pattern_args(load: LoadRpc) -> String {
  let args =
    server_ssr_route_args(load)
    |> list.map(fn(pair) { pair.0 <> ":" })

  case args {
    [] -> ""
    _ -> "(" <> string.join(args, ", ") <> ")"
  }
}

fn server_ssr_route_args(load: LoadRpc) -> List(#(String, LoadArg)) {
  list.zip(server_ssr_dynamic_segments(load), load.args)
}

fn server_ssr_dynamic_segments(load: LoadRpc) -> List(String) {
  load.module_path
  |> page_segments_from_module
  |> list.map(fn(segment) {
    case string.ends_with(segment, "_") {
      True -> Some(string.drop_end(segment, 1))
      False -> None
    }
  })
  |> option.values
}

fn server_ssr_route_constructor(load: LoadRpc) -> String {
  route_constructor_for_module(load.module_path)
}

fn route_message_constructor(module_path: String) -> String {
  route_constructor_for_module(module_path) <> "Msg"
}

fn navigation_message_constructor(module_path: String) -> String {
  "Navigate" <> navigation_target_name(module_path)
}

fn navigation_target_name(module_path: String) -> String {
  module_path
  |> page_segments_from_module
  |> list.filter(fn(segment) {
    !string.ends_with(segment, "_")
    && segment != "home_"
    && segment != "not_found_"
  })
  |> list.last
  |> result.unwrap("")
  |> singular_path_segment
  |> pascal_path_segment
}

fn singular_path_segment(segment: String) -> String {
  case string.ends_with(segment, "s") {
    True -> string.drop_end(segment, 1)
    False -> segment
  }
}

fn route_constructor_for_module(module_path: String) -> String {
  let mount = load_mount_from_module(module_path)
  let base =
    module_path
    |> page_segments_from_module
    |> list.map(pascal_path_segment)
    |> string.join("")

  case mount {
    "public" -> base
    _ -> mount_type_prefix(mount) <> base
  }
}

fn dynamic_segments_from_module(module_path: String) -> List(String) {
  module_path
  |> page_segments_from_module
  |> list.map(fn(segment) {
    case segment, string.ends_with(segment, "_") {
      "home_", _ -> None
      "not_found_", _ -> None
      _, True -> Some(string.drop_end(segment, 1))
      _, False -> None
    }
  })
  |> option.values
}

fn page_segments_from_module(module_path: String) -> List(String) {
  module_path
  |> string.split("/")
  |> drop_pages_prefix
}

fn pascal_path_segment(segment: String) -> String {
  segment
  |> string.drop_end(case string.ends_with(segment, "_") {
    True -> 1
    False -> 0
  })
  |> pascal_segment
}

fn page_module_alias(module_path: String) -> String {
  module_path
  |> to_snake_case
  |> string.replace("/", "_")
  |> fn(name) { name <> "_page" }
}

fn drop_pages_prefix(parts: List(String)) -> List(String) {
  case parts {
    [_, "pages", ..rest] -> rest
    [_, ..rest] -> drop_pages_prefix(rest)
    [] -> []
  }
}

fn pascal_segment(segment: String) -> String {
  case string.pop_grapheme(segment) {
    Ok(#(first, rest)) -> string.uppercase(first) <> rest
    Error(Nil) -> segment
  }
}

fn server_ssr_hydration_payload(load: LoadRpc) -> String {
  "@target(erlang)
pub fn " <> load.name <> "_hydration_payload(
  result result: Result(" <> wire_alias(load) <> ".LoadResult, List(String)),
) -> String {
  server_protocol.ensure()
  result
  |> map_load_result
  |> server_protocol.encode_" <> load.name <> "_load_result(request_id: 0)
  |> bit_array.base64_url_encode(False)
}
"
}

fn hydration_load_result(load: LoadRpc) -> String {
  "@target(javascript)
pub fn " <> load.name <> "_load_result() -> Result(
  Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)),
  Nil,
) {
  case browser.take_boot_string(\"hydration\") {
    \"\" -> Error(Nil)
    raw ->
      case string.split(raw, \",\") {
        [encoded, ..] -> decode_" <> load.name <> "_load_result(encoded)
        [] -> Error(Nil)
      }
  }
}
"
}

fn hydration_decode_result(load: LoadRpc) -> String {
  "@target(javascript)
fn decode_" <> load.name <> "_load_result(
  encoded: String,
) -> Result(Result(" <> client_load_result_type(load) <> ", List(ApiLoadError)), Nil) {
  case bit_array.base64_url_decode(encoded) {
    Ok(bytes) ->
      case client_protocol.decode_" <> load.name <> "_load_result(bytes) {
        Ok(#(_, result)) -> Ok(result)
        Error(Nil) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}
"
}

fn client_load_result_type(load: LoadRpc) -> String {
  use <- bool.guard(when: !load.import_on_client, return: "load_result")
  wire_alias(load) <> ".LoadResult"
}

fn client_save_result_type(load: LoadRpc) -> String {
  case load.import_on_client, load.save_result_type {
    True, Some(save_result_type) -> wire_alias(load) <> "." <> save_result_type
    _, _ -> "save_result"
  }
}

fn wire_encoder_function(module_path: String, type_name: String) -> String {
  "encode_"
  <> string.replace(module_path, "/", "_")
  <> "__"
  <> to_snake_case(type_name)
}

fn has_custom_type(
  custom_types: List(glance.Definition(glance.CustomType)),
  name: String,
) -> Bool {
  list.any(custom_types, fn(def) { def.definition.name == name })
}

fn to_snake_case(name: String) -> String {
  case string.to_graphemes(name) {
    [] -> ""
    [first, ..rest] -> to_snake_case_loop(rest, string.lowercase(first))
  }
}

fn to_snake_case_loop(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    [char, ..rest] -> {
      let lower = string.lowercase(char)
      let prefix = case char != lower && acc != "" {
        True -> "_"
        False -> ""
      }
      to_snake_case_loop(rest, acc <> prefix <> lower)
    }
  }
}
