// Browser-side effect FFI for rally/runtime/effect.gleam

export function navigate(path) {
  globalThis.history?.pushState(null, "", path);
  globalThis.dispatchEvent(new PopStateEvent("popstate"));
}
