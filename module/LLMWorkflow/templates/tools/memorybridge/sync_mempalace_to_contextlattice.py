#!/usr/bin/env python3
"""Incremental one-way bridge: MemPalace -> ContextLattice."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import PurePath
from typing import Any
from urllib import error, request

import chromadb


def _load_json(path: str) -> dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def _save_json(path: str, payload: dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def _slug(value: str, fallback: str = "unknown") -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9._-]+", "-", (value or "").strip().lower()).strip("-")
    return cleaned or fallback


def _as_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def _post_json(url: str, api_key: str, payload: dict[str, Any], timeout: int = 30) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(
        url=url,
        data=body,
        method="POST",
        headers={
            "content-type": "application/json",
            "x-api-key": api_key,
        },
    )
    with request.urlopen(req, timeout=timeout) as resp:
        text = resp.read().decode("utf-8", errors="replace")
        if not text.strip():
            return {}
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"raw": text}


def _get_json(url: str, api_key: str, timeout: int = 15) -> dict[str, Any]:
    req = request.Request(
        url=url,
        method="GET",
        headers={
            "x-api-key": api_key,
        },
    )
    with request.urlopen(req, timeout=timeout) as resp:
        text = resp.read().decode("utf-8", errors="replace")
        if not text.strip():
            return {}
        return json.loads(text)


def _resolve(name: str, arg_val: str, config_val: str, env_val: str, default: str) -> str:
    if arg_val:
        return arg_val
    if env_val:
        return env_val
    if config_val:
        return config_val
    return default


def _extract_wing_map(config: dict[str, Any]) -> dict[str, str]:
    wing_map = config.get("wingProjectMap", {})
    if isinstance(wing_map, dict):
        return {str(k): str(v) for k, v in wing_map.items()}
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync MemPalace drawers into ContextLattice")
    parser.add_argument("--config-file", default=".memorybridge/bridge.config.json")
    parser.add_argument("--state-file", default=".memorybridge/sync-state.json")
    parser.add_argument("--orchestrator-url", default="")
    parser.add_argument("--api-key", default="")
    parser.add_argument("--api-key-env-var", default="")
    parser.add_argument("--palace-path", default="")
    parser.add_argument("--collection-name", default="")
    parser.add_argument("--default-project-name", default="")
    parser.add_argument("--topic-prefix", default="")
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-resync", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    config = _load_json(args.config_file)
    state = _load_json(args.state_file)
    synced: dict[str, str] = state.get("synced", {}) if isinstance(state.get("synced"), dict) else {}
    state.setdefault("version", 1)

    api_key_env_var = _resolve(
        "api_key_env_var",
        args.api_key_env_var,
        _as_text(config.get("apiKeyEnvVar")),
        "",
        "CONTEXTLATTICE_ORCHESTRATOR_API_KEY",
    )
    api_key = _resolve(
        "api_key",
        args.api_key,
        "",
        os.environ.get(api_key_env_var, ""),
        "",
    )
    orchestrator_url = _resolve(
        "orchestrator_url",
        args.orchestrator_url,
        _as_text(config.get("orchestratorUrl")),
        os.environ.get("CONTEXTLATTICE_ORCHESTRATOR_URL", ""),
        "http://127.0.0.1:8075",
    ).rstrip("/")
    palace_path = os.path.expanduser(
        _resolve(
            "palace_path",
            args.palace_path,
            _as_text(config.get("palacePath")),
            os.environ.get("MEMPALACE_PALACE_PATH", ""),
            "~/.mempalace/palace",
        )
    )
    collection_name = _resolve(
        "collection_name",
        args.collection_name,
        _as_text(config.get("collectionName")),
        "",
        "mempalace_drawers",
    )
    default_project = _resolve(
        "default_project",
        args.default_project_name,
        _as_text(config.get("defaultProjectName")),
        "",
        "default_project",
    )
    topic_prefix = _resolve(
        "topic_prefix",
        args.topic_prefix,
        _as_text(config.get("topicPrefix")),
        "",
        "mempalace",
    )
    wing_project_map = _extract_wing_map(config)

    if not os.path.isdir(palace_path):
        print(json.dumps({"error": f"Palace path does not exist: {palace_path}"}))
        return 2

    if not args.dry_run and not api_key:
        print(json.dumps({"error": f"Missing API key. Set --api-key or env var {api_key_env_var}."}))
        return 2

    if args.batch_size <= 0:
        print(json.dumps({"error": "--batch-size must be > 0"}))
        return 2

    if not args.dry_run:
        try:
            _ = _get_json(f"{orchestrator_url}/status", api_key)
        except Exception as exc:
            print(json.dumps({"error": f"ContextLattice status check failed: {exc}"}))
            return 2

    client = chromadb.PersistentClient(path=palace_path)
    try:
        collection = client.get_collection(collection_name)
    except Exception as exc:
        msg = str(exc).lower()
        if "does not exist" in msg or "not found" in msg:
            print(
                json.dumps(
                    {
                        "mode": "dry_run" if args.dry_run else "write",
                        "orchestratorUrl": orchestrator_url,
                        "palacePath": palace_path,
                        "collectionName": collection_name,
                        "seen": 0,
                        "candidateWrites": 0,
                        "writesSucceeded": 0,
                        "writesFailed": 0,
                        "skippedUnchanged": 0,
                        "note": f"Collection '{collection_name}' does not exist yet.",
                    },
                    indent=2,
                )
            )
            return 0
        print(json.dumps({"error": f"Could not open collection '{collection_name}': {exc}"}))
        return 2

    summary = {
        "mode": "dry_run" if args.dry_run else "write",
        "orchestratorUrl": orchestrator_url,
        "palacePath": palace_path,
        "collectionName": collection_name,
        "defaultProjectName": default_project,
        "topicPrefix": topic_prefix,
        "seen": 0,
        "candidateWrites": 0,
        "writesSucceeded": 0,
        "writesFailed": 0,
        "skippedUnchanged": 0,
        "errors": [],
    }

    processed_writes = 0
    offset = 0
    stop = False

    while not stop:
        batch = collection.get(
            include=["documents", "metadatas"],
            limit=args.batch_size,
            offset=offset,
        )
        ids = batch.get("ids", []) or []
        docs = batch.get("documents", []) or []
        metas = batch.get("metadatas", []) or []
        if not ids:
            break

        for idx, drawer_id in enumerate(ids):
            summary["seen"] += 1
            doc = _as_text(docs[idx] if idx < len(docs) else "")
            meta = metas[idx] if idx < len(metas) and isinstance(metas[idx], dict) else {}
            content_hash = hashlib.sha256(doc.encode("utf-8")).hexdigest()

            if not args.force_resync and synced.get(drawer_id) == content_hash:
                summary["skippedUnchanged"] += 1
                continue

            if args.limit > 0 and processed_writes >= args.limit:
                stop = True
                break

            wing = _as_text(meta.get("wing", "general"))
            room = _as_text(meta.get("room", "general"))
            source_file = _as_text(meta.get("source_file", "source"))
            source_stem = _slug(PurePath(source_file).stem or "source")
            wing_slug = _slug(wing)
            room_slug = _slug(room)

            project_name = wing_project_map.get(wing) or default_project
            topic_path = "/".join([_slug(topic_prefix, "mempalace"), wing_slug, room_slug])
            file_name = f"mempalace/{wing_slug}/{room_slug}/{_slug(drawer_id)}-{source_stem}.md"

            payload = {
                "projectName": project_name,
                "fileName": file_name,
                "content": doc,
                "topicPath": topic_path,
            }

            summary["candidateWrites"] += 1
            processed_writes += 1

            if args.dry_run:
                continue

            try:
                result = _post_json(f"{orchestrator_url}/memory/write", api_key, payload)
                if isinstance(result, dict) and result.get("ok") is False:
                    raise RuntimeError(f"memory/write returned ok=false: {result}")
                synced[drawer_id] = content_hash
                summary["writesSucceeded"] += 1
            except Exception as exc:
                summary["writesFailed"] += 1
                summary["errors"].append(
                    {
                        "drawerId": drawer_id,
                        "error": str(exc),
                    }
                )
                if args.strict:
                    stop = True
                    break

        offset += len(ids)

    state["synced"] = synced
    state["lastRunUtc"] = datetime.now(timezone.utc).isoformat()
    state["lastSummary"] = {
        "seen": summary["seen"],
        "candidateWrites": summary["candidateWrites"],
        "writesSucceeded": summary["writesSucceeded"],
        "writesFailed": summary["writesFailed"],
        "skippedUnchanged": summary["skippedUnchanged"],
        "mode": summary["mode"],
    }
    if not args.dry_run:
        _save_json(args.state_file, state)

    print(json.dumps(summary, indent=2))
    return 0 if summary["writesFailed"] == 0 else 3


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(json.dumps({"error": f"HTTP {exc.code}", "detail": detail}))
        raise SystemExit(2)
    except Exception as exc:
        print(json.dumps({"error": str(exc)}))
        raise SystemExit(2)
