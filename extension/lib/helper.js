// Client for the optional macOS helper running on 127.0.0.1.

async function request(port, path, init = {}, timeoutMs = 800) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`http://127.0.0.1:${port}${path}`, { ...init, signal: controller.signal });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null; // helper not running — callers fall back gracefully
  } finally {
    clearTimeout(timer);
  }
}

export function fetchSnippet(port) {
  return request(port, "/snippet");
}

export function fetchStatus(port) {
  return request(port, "/status");
}

/** entry.kind: "Unlocked" (default) or "Reflection". */
export function postReason(port, entry) {
  return request(
    port,
    "/reasons",
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(entry) },
    2000,
  );
}
