#!/usr/bin/env python3
"""
NOEMA UI audit: catches the visual-defect classes that unit tests miss.

The page is served under `Content-Security-Policy: style-src 'self'`, which rejects inline
`style=` attributes and — less obviously — silently ignores `element.style.width = ...`. A UI can
look "fine" in a source review and still render dead progress bars, "hidden" panels that are
visible, or text at 3:1 contrast. Those are exactly the bugs this script measures in a real
browser, at three widths, on all three pages.

Checks, per page and viewport:

  1. `[hidden]` elements really have `display:none` (no component overrides it).
  2. Every visible progress bar/track has a measurable fill.
  3. No rendered text is below 9px.
  4. No horizontal overflow.
  5. Every control is reachable: nothing stays under a fixed/sticky bar when the page is
     scrolled to its end.
  6. Small text meets WCAG AA contrast (4.5:1) against its own effective background.
  7. No console errors (CSP violations are reported here).

Usage:
    python3 ai/noema_v3/ui_audit.py            # start a server, audit, tear down
    python3 ai/noema_v3/ui_audit.py --url http://127.0.0.1:4173

Exit code 0 only when every check passes. When no browser is available the script reports SKIP
rather than failing a run that could not be measured.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
PAGES = ["/", "/pretraining", "/system"]
WIDTHS = [1440, 820, 420]

# ---------------------------------------------------------------------------------------------
# browser discovery
# ---------------------------------------------------------------------------------------------


def find_chrome() -> tuple[str, dict[str, str]] | None:
    """Return (executable, env) for a Chromium build this script can drive."""
    env = dict(os.environ)
    # A Chromium unpacked from an npm bundle needs its bundled libnss/libnspr beside it.
    for libdir in ("/tmp/chrome-libs/lib",):
        if pathlib.Path(libdir).is_dir():
            env["LD_LIBRARY_PATH"] = libdir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    for candidate in ("/tmp/chrome.bin", "/usr/bin/chromium", "/usr/bin/google-chrome", "/usr/bin/chromium-browser"):
        if pathlib.Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate, env
    for name in ("chromium", "google-chrome", "chrome"):
        found = shutil.which(name)
        if found:
            return found, env
    return None


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


# ---------------------------------------------------------------------------------------------
# in-page audit expression
# ---------------------------------------------------------------------------------------------

AUDIT_JS = r"""
(() => {
  const out = {};
  const M = (name, list) => { out[name] = list; };

  // Anything inside a display:none / visibility:hidden subtree is not on screen and must not be
  // judged: hidden panels legitimately hold zero-height progress tracks.
  const isShown = el => {
    for (let n = el; n && n !== document.documentElement; n = n.parentElement) {
      if (n.hasAttribute && n.hasAttribute('hidden')) return false;
      const cs = getComputedStyle(n);
      if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    }
    return true;
  };

  // 1) the `hidden` attribute must actually hide
  M('hiddenVisible', [...document.querySelectorAll('[hidden]')]
    .filter(el => getComputedStyle(el).display !== 'none' || el.getBoundingClientRect().height > 0)
    .map(el => ({ sel: el.id || String(el.className).slice(0, 30) })));

  // 2) visible progress bars need a fill
  M('deadBars', [...document.querySelectorAll('.bar, .track')]
    .filter(bar => bar.querySelector('i') && isShown(bar))
    .filter(bar => {
      const i = bar.querySelector('i');
      return bar.getBoundingClientRect().height < 2 || i.getBoundingClientRect().height < 1;
    })
    .map(bar => ({ id: bar.id || '(anon)' })));

  // 3) no unreadably small text
  const tinySeen = new Set();
  const tiny = [];
  for (const el of document.querySelectorAll('*')) {
    const hasText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (!hasText || !isShown(el)) continue;
    const px = parseFloat(getComputedStyle(el).fontSize);
    if (px && px < 9 && !tinySeen.has(px)) {
      tinySeen.add(px);
      tiny.push({ px, tag: el.tagName, cls: String(el.className).slice(0, 30) });
    }
  }
  M('tinyText', tiny);

  // 4) no horizontal overflow
  const docW = document.documentElement.clientWidth;
  M('overflow', document.documentElement.scrollWidth > docW
    ? [{ by: document.documentElement.scrollWidth - docW }] : []);

  // 5) reachability at the end of the document
  const scrollY = window.scrollY;
  window.scrollTo(0, document.documentElement.scrollHeight);
  const occluded = [];
  for (const bar of document.querySelectorAll('.composer-wrap, .rail, .topbar')) {
    const cs = getComputedStyle(bar);
    if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
    const r = bar.getBoundingClientRect();
    if (!r.height) continue;
    for (const cand of document.querySelectorAll('button, a, input, textarea, select, summary')) {
      if (cand === bar || bar.contains(cand)) continue;
      const cr = cand.getBoundingClientRect();
      if (!cr.height || !cr.width) continue;
      const oy = Math.min(cr.bottom, r.bottom) - Math.max(cr.top, r.top);
      const ox = Math.min(cr.right, r.right) - Math.max(cr.left, r.left);
      if (oy > 6 && ox > 6) {
        occluded.push({
          el: (cand.id || String(cand.className) || cand.tagName).slice(0, 34),
          by: String(bar.className).slice(0, 20),
          px: Math.round(oy),
        });
      }
    }
  }
  window.scrollTo(0, scrollY);
  M('occluded', occluded);

  // 6) WCAG AA contrast for small text
  const lum = rgb => {
    const f = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]);
  };
  const parse = s => {
    const m = s.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(',').map(Number);
    return { rgb: p.slice(0, 3), a: p.length > 3 ? p[3] : 1 };
  };
  const bgOf = el => {
    for (let n = el; n && n !== document.documentElement; n = n.parentElement) {
      const c = parse(getComputedStyle(n).backgroundColor);
      if (c && c.a > 0.5) return c.rgb;
    }
    return [8, 10, 18];
  };
  const lowContrast = [];
  for (const el of document.querySelectorAll('span, small, p, strong, td, th, dt, dd, a, button, label, summary, code, pre, h1, h2, h3')) {
    if (![...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim().length > 2)) continue;
    if (!isShown(el)) continue;
    const cs = getComputedStyle(el);
    if (parseFloat(cs.opacity) < 0.5) continue;
    const rect = el.getBoundingClientRect();
    if (rect.width < 4 || rect.height < 4) continue;
    const fg = parse(cs.color);
    if (!fg) continue;
    const L1 = lum(fg.rgb);
    const L2 = lum(bgOf(el));
    const ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
    const px = parseFloat(cs.fontSize);
    const large = px >= 18.66 || (px >= 14 && parseInt(cs.fontWeight, 10) >= 700);
    const need = large ? 3 : 4.5;
    if (ratio < need && lowContrast.length < 25) {
      lowContrast.push({
        text: el.textContent.trim().slice(0, 26),
        px,
        ratio: Math.round(ratio * 100) / 100,
        need,
        cls: String(el.className).slice(0, 26),
      });
    }
  }
  M('lowContrast', lowContrast);

  return out;
})()
"""


# ---------------------------------------------------------------------------------------------
# CDP driver (no external dependencies)
# ---------------------------------------------------------------------------------------------


class DevTools:
    def __init__(self, port: int):
        self.base = f"http://127.0.0.1:{port}"
        self.id = 0
        self.pending: dict[int, object] = {}
        self.events: list[dict] = []
        self.ws = None

    def wait(self, timeout: float = 30.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                urllib.request.urlopen(self.base + "/json/version", timeout=1).read()
                return
            except Exception:
                time.sleep(0.25)
        raise RuntimeError("Chromium DevTools endpoint did not come up")

    def open_page(self) -> str:
        req = urllib.request.Request(self.base + "/json/new?about:blank", method="PUT")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read())["webSocketDebuggerUrl"]

# A minimal synchronous WebSocket client keeps this script dependency-free. It speaks just enough
# of RFC 6455 for CDP: a single client, text frames, no extensions.
class MiniWs:
    def __init__(self, url: str):
        from urllib.parse import urlparse
        import base64
        import socket as sock

        parsed = urlparse(url)
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        path = parsed.path + (f"?{parsed.query}" if parsed.query else "")
        self.sock = sock.create_connection((host, port), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        handshake = (
            f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(handshake.encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("WebSocket handshake failed")
            buf += chunk
        if b"101" not in buf.split(b"\r\n", 1)[0]:
            raise RuntimeError(f"WebSocket upgrade rejected: {buf[:120]!r}")
        self.buf = buf.split(b"\r\n\r\n", 1)[1]

    def send_text(self, text: str) -> None:
        payload = text.encode()
        header = bytearray([0x81])
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += n.to_bytes(2, "big")
        else:
            header.append(0x80 | 127)
            header += n.to_bytes(8, "big")
        mask = os.urandom(4)
        header += mask
        self.sock.sendall(bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def _read(self, n: int) -> bytes:
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("socket closed")
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def recv_text(self) -> str:
        while True:
            b0, b1 = self._read(2)
            opcode = b0 & 0x0F
            length = b1 & 0x7F
            if length == 126:
                length = int.from_bytes(self._read(2), "big")
            elif length == 127:
                length = int.from_bytes(self._read(8), "big")
            payload = self._read(length)
            if opcode == 0x1:
                return payload.decode()
            if opcode == 0x8:
                raise ConnectionError("server closed")
            # ping/pong/continuation are ignored: CDP replies are single text frames

    def close(self) -> None:
        try:
            self.sock.close()
        except Exception:
            pass


class Session:
    def __init__(self, ws_url: str):
        self.ws = MiniWs(ws_url)
        self.id = 0
        self.events: list[dict] = []

    def call(self, method: str, params: dict | None = None):
        self.id += 1
        want = self.id
        self.ws.send_text(json.dumps({"id": want, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv_text())
            if msg.get("id") == want:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error'].get('message')}")
                return msg.get("result", {})
            self.events.append(msg)

    def evaluate(self, expression: str):
        result = self.call("Runtime.evaluate", {"expression": expression, "returnByValue": True, "awaitPromise": True})
        if result.get("exceptionDetails"):
            raise RuntimeError(result["exceptionDetails"].get("text", "evaluation failed"))
        return result.get("result", {}).get("value")

    def drain_errors(self) -> list[str]:
        found = [e["params"]["entry"]["text"] for e in self.events
                 if e.get("method") == "Log.entryAdded" and e["params"]["entry"].get("level") == "error"]
        self.events = [e for e in self.events if e.get("method") != "Log.entryAdded"]
        return found


# ---------------------------------------------------------------------------------------------


def run(url: str) -> int:
    found = find_chrome()
    if not found:
        print("SKIP: no Chromium available to audit the UI")
        return 0
    chrome_path, chrome_env = found

    port = free_port()
    chrome = subprocess.Popen(
        [
            chrome_path, "--headless=new", f"--remote-debugging-port={port}", "--no-sandbox",
            "--disable-gpu", "--use-gl=swiftshader", "--disable-dev-shm-usage",
            "--in-process-gpu", "--hide-scrollbars",
        ],
        env=chrome_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    failures: list[str] = []
    checks = 0
    try:
        probe = DevTools(port)
        probe.wait()
        ws_url = probe.open_page()
        session = Session(ws_url)
        session.call("Page.enable")
        session.call("Runtime.enable")
        session.call("Log.enable")

        for page in PAGES:
            for width in WIDTHS:
                label = f"{page} @ {width}px"
                session.call("Emulation.setDeviceMetricsOverride",
                             {"width": width, "height": 900, "deviceScaleFactor": 1, "mobile": width < 500})
                session.call("Page.navigate", {"url": url.rstrip("/") + page})
                time.sleep(2.2)
                data = session.evaluate(AUDIT_JS) or {}

                def check(condition: bool, name: str, detail: str = "") -> None:
                    nonlocal checks
                    checks += 1
                    if condition:
                        print(f"  [OK]   {label}: {name}")
                    else:
                        print(f"  [FAIL] {label}: {name}{' — ' + detail if detail else ''}")
                        failures.append(f"{label}: {name}")

                check(not data.get("hiddenVisible"), "hidden elements are hidden",
                      str(data.get("hiddenVisible")[:2]))
                check(not data.get("deadBars"), "all visible bars have a fill",
                      str(data.get("deadBars")[:2]))
                check(not data.get("tinyText"), "no text below 9px",
                      str(data.get("tinyText")[:2]))
                check(not data.get("overflow"), "no horizontal overflow",
                      str(data.get("overflow")))
                check(not data.get("occluded"), "every control is reachable",
                      str(data.get("occluded")[:2]))
                check(not data.get("lowContrast"), "small text meets WCAG AA (4.5:1)",
                      str(data.get("lowContrast")[:2]))
                errors = session.drain_errors()
                check(not errors, "no console errors", (errors[0][:110] if errors else ""))
    finally:
        chrome.terminate()
        try:
            chrome.wait(timeout=10)
        except subprocess.TimeoutExpired:
            chrome.kill()

    print()
    if failures:
        print(f"NOEMA UI AUDIT: FAIL: {len(failures)} of {checks} checks")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print(f"NOEMA UI AUDIT: {checks}/{checks} checks PASS across {len(PAGES)} pages x {len(WIDTHS)} widths")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="", help="audit an already running server instead of starting one")
    args = parser.parse_args()

    if args.url:
        return run(args.url)

    if not (ROOT / "zig-out" / "bin" / "noema_v3_chat_backend").exists():
        print("SKIP: noema_v3_chat_backend is not built")
        return 0

    port = free_port()
    env = dict(os.environ, PORT=str(port), LIR_BIN=str(ROOT / "zig-out" / "bin" / "lir"))
    server = subprocess.Popen(
        ["node", "apps/noema-chat/server.mjs"], cwd=ROOT, env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        base = f"http://127.0.0.1:{port}"
        for _ in range(120):
            try:
                urllib.request.urlopen(base + "/api/health", timeout=2).read()
                break
            except Exception:
                time.sleep(0.25)
        return run(base)
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()


if __name__ == "__main__":
    sys.exit(main())
