#!/usr/bin/env python3
"""Minimal mock ContextLattice server for integration tests."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


def _read_json_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return {}
    body = handler.rfile.read(length).decode("utf-8", errors="replace")
    if not body.strip():
        return {}
    return json.loads(body)


class MockContextLatticeHandler(BaseHTTPRequestHandler):
    server_version = "MockContextLattice/0.1"
    state: dict[str, Any] = {}
    state_file: Path | None = None
    api_key: str = ""

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _persist(self) -> None:
        if not self.state_file:
            return
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps(self.state, indent=2), encoding="utf-8")

    def _require_api_key(self) -> bool:
        if not self.api_key:
            return True
        got = self.headers.get("x-api-key", "")
        if got == self.api_key:
            return True
        self._json(401, {"ok": False, "error": "unauthorized"})
        return False

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._json(200, {"ok": True})
            return
        if self.path == "/status":
            if not self._require_api_key():
                return
            self._json(200, {"service": "mock-contextlattice", "sinks": {"memory": "ok"}})
            return
        self._json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path in {"/memory/write", "/memory/search"} and not self._require_api_key():
            return

        if self.path == "/memory/write":
            payload = _read_json_body(self)
            self.state.setdefault("writes", []).append(payload)
            self._persist()
            self._json(200, {"ok": True})
            return

        if self.path == "/memory/search":
            payload = _read_json_body(self)
            query = str(payload.get("query", ""))
            results = []
            for item in self.state.get("writes", []):
                content = str(item.get("content", ""))
                if query and query in content:
                    results.append(
                        {
                            "projectName": item.get("projectName", ""),
                            "fileName": item.get("fileName", ""),
                            "topicPath": item.get("topicPath", ""),
                        }
                    )
            self.state.setdefault("searches", []).append(payload)
            self._persist()
            self._json(200, {"results": results})
            return

        self._json(404, {"ok": False, "error": "not_found"})

    def log_message(self, format: str, *args: Any) -> None:
        return


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--api-key", default="")
    parser.add_argument("--state-file", default="")
    args = parser.parse_args()

    MockContextLatticeHandler.api_key = args.api_key
    MockContextLatticeHandler.state = {"writes": [], "searches": []}
    if args.state_file:
        MockContextLatticeHandler.state_file = Path(args.state_file).expanduser().resolve()
        MockContextLatticeHandler.state_file.parent.mkdir(parents=True, exist_ok=True)
        MockContextLatticeHandler.state_file.write_text(
            json.dumps(MockContextLatticeHandler.state, indent=2), encoding="utf-8"
        )

    server = ThreadingHTTPServer((args.host, args.port), MockContextLatticeHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

