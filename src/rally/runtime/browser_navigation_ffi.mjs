export function push_path(path) {
  const history = globalThis.history;
  const location = globalThis.location;
  if (!history || !location) return;

  const current = location.pathname + location.search;
  if (current === path) return;

  history.pushState(null, "", path);
}

export function navigate(path) {
  push_path(path);
  globalThis.dispatchEvent?.(new PopStateEvent("popstate"));
}

export function listen_shell_navigation(dispatch) {
  globalThis.document?.addEventListener?.("click", event => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    const link = event.target?.closest?.("a[data-rally-spa-nav]");
    if (!link) return;
    if (link.target === "_blank" || link.hasAttribute("download")) return;

    const location = globalThis.location;
    if (!location) return;

    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin) return;

    const destination = url.pathname + url.search;
    const current = location.pathname + location.search;
    if (destination === current) {
      if (url.hash && url.hash !== location.hash) return;
      event.preventDefault();
      return;
    }

    event.preventDefault();
    dispatch(destination);
  });
}
