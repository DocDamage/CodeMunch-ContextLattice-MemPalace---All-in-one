#!/usr/bin/env python3
"""Incremental one-way bridge: ContextLattice -> MemPalace."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
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
    headers = {}
    if api_key:
        headers["x-api-key"] = api_key
    req = request.Request(
        url=url,
        method="GET",
        headers=headers,
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


def _append_history(history_path: str, entry: dict[str, Any], max_entries: int) -> None:
    """Append JSON line to history file and trim oldest entries when exceeding max_entries."""
    if not history_path:
        return

    # Ensure directory exists
    history_dir = os.path.dirname(os.path.abspath(history_path))
    if history_dir:
        os.makedirs(history_dir, exist_ok=True)

    # Append entry as JSON line
    with open(history_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")

    # Trim oldest entries if exceeding max_entries
    if max_entries > 0:
        try:
            with open(history_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
            if len(lines) > max_entries:
                # Keep only the most recent entries
                lines = lines[-max_entries:]
                with open(history_path, "w", encoding="utf-8") as f:
                    f.writelines(lines)
        except Exception:
            # Ignore errors when trimming history
            pass


def _compute_memory_id(memory: dict[str, Any]) -> str:
    """Compute a unique ID for a memory based on its content."""
    # Use memory id if available, otherwise hash content
    mem_id = memory.get("id")
    if mem_id:
        return str(mem_id)
    # Fall back to hashing fileName + content
    file_name = _as_text(memory.get("fileName", ""))
    content = _as_text(memory.get("content", ""))
    return hashlib.sha256(f"{file_name}:{content}".encode("utf-8")).hexdigest()


def _extract_metadata(memory: dict[str, Any]) -> dict[str, str]:
    """Extract metadata from a ContextLattice memory for ChromaDB."""
    meta = {}
    
    # Extract project name
    project = memory.get("projectName") or memory.get("project")
    if project:
        meta["project"] = _as_text(project)
    
    # Extract topic path and derive wing/room
    topic_path = memory.get("topicPath") or memory.get("topic")
    if topic_path:
        meta["topic_path"] = _as_text(topic_path)
        parts = topic_path.split("/")
        if len(parts) >= 1:
            meta["wing"] = parts[0]
        if len(parts) >= 2:
            meta["room"] = parts[1]
        if len(parts) >= 3:
            meta["drawer"] = parts[2]
    
    # Extract file name
    file_name = memory.get("fileName") or memory.get("file")
    if file_name:
        meta["source_file"] = _as_text(file_name)
    
    # Extract timestamps
    created = memory.get("createdAt") or memory.get("created")
    if created:
        meta["created"] = _as_text(created)
    
    updated = memory.get("updatedAt") or memory.get("updated")
    if updated:
        meta["updated"] = _as_text(updated)
    
    # Add sync source marker
    meta["sync_source"] = "contextlattice"
    
    return meta


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync ContextLattice memories into MemPalace")
    parser.add_argument("--config-file", default=".memorybridge/bridge.config.json")
    parser.add_argument("--state-file", default=".memorybridge/sync-state.json")
    parser.add_argument("--history-file", default=".memorybridge/sync-history-reverse.jsonl")
    parser.add_argument("--history-max-entries", type=int, default=500)
    parser.add_argument("--orchestrator-url", default="")
    parser.add_argument("--api-key", default="")
    parser.add_argument("--api-key-env-var", default="")
    parser.add_argument("--palace-path", default="")
    parser.add_argument("--collection-name", default="")
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-resync", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    config = _load_json(args.config_file)
    state = _load_json(args.state_file)
    
    # Use separate synced tracking for reverse direction
    synced: dict[str, str] = {}
    if isinstance(state.get("syncedReverse"), dict):
        synced = state.get("syncedReverse", {})
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

    if not args.dry_run and not api_key:
        print(json.dumps({"error": f"Missing API key. Set --api-key or env var {api_key_env_var}."}))
        return 2

    if args.batch_size <= 0:
        print(json.dumps({"error": "--batch-size must be > 0"}))
        return 2

    # Test connectivity
    if not args.dry_run:
        try:
            _ = _get_json(f"{orchestrator_url}/status", api_key)
        except Exception as exc:
            print(json.dumps({"error": f"ContextLattice status check failed: {exc}"}))
            return 2

    # Initialize ChromaDB client
    if not os.path.isdir(palace_path):
        if args.dry_run:
            print(json.dumps({
                "mode": "dry_run",
                "note": f"Palace path does not exist: {palace_path}. Would create in write mode."
            }))
        else:
            os.makedirs(palace_path, exist_ok=True)

    client = chromadb.PersistentClient(path=palace_path)
    
    # Get or create collection
    try:
        collection = client.get_collection(collection_name)
    except Exception:
        if args.dry_run:
            print(json.dumps({
                "mode": "dry_run",
                "note": f"Collection '{collection_name}' does not exist. Would create in write mode."
            }))
            return 0
        try:
            collection = client.create_collection(collection_name)
        except Exception as exc:
            print(json.dumps({"error": f"Could not create collection '{collection_name}': {exc}"}))
            return 2

    summary = {
        "mode": "dry_run" if args.dry_run else "write",
        "orchestratorUrl": orchestrator_url,
        "palacePath": palace_path,
        "collectionName": collection_name,
        "seen": 0,
        "candidateWrites": 0,
        "writesSucceeded": 0,
        "writesFailed": 0,
        "skippedUnchanged": 0,
        "errors": [],
    }

    # Fetch memories from ContextLattice
    memories: list[dict[str, Any]] = []
    offset = 0
    stop_fetch = False

    try:
        while not stop_fetch:
            # Use /memory/list endpoint with pagination
            list_url = f"{orchestrator_url}/memory/list?limit={args.batch_size}&offset={offset}"
            try:
                response = _get_json(list_url, api_key)
            except error.HTTPError as exc:
                if exc.code == 404:
                    # Fallback to /memory/search with empty query for all memories
                    search_url = f"{orchestrator_url}/memory/search"
                    payload = {
                        "query": "",
                        "limit": args.batch_size,
                        "offset": offset,
                    }
                    response = _post_json(search_url, api_key, payload)
                else:
                    raise

            items = response.get("memories") or response.get("results") or response.get("items") or []
            if not isinstance(items, list):
                items = []

            for mem in items:
                if not isinstance(mem, dict):
                    continue
                memories.append(mem)

            if len(items) < args.batch_size:
                stop_fetch = True
            else:
                offset += len(items)

            # Safety limit
            if args.limit > 0 and len(memories) >= args.limit:
                memories = memories[:args.limit]
                stop_fetch = True

    except Exception as exc:
        print(json.dumps({"error": f"Failed to fetch memories from ContextLattice: {exc}"}))
        return 2

    # Process memories and sync to ChromaDB
    for memory in memories:
        summary["seen"] += 1
        
        mem_id = _compute_memory_id(memory)
        content = _as_text(memory.get("content", ""))
        
        if not content.strip():
            summary["skippedUnchanged"] += 1
            continue

        content_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()

        if not args.force_resync and synced.get(mem_id) == content_hash:
            summary["skippedUnchanged"] += 1
            continue

        summary["candidateWrites"] += 1

        if args.dry_run:
            continue

        # Extract metadata
        meta = _extract_metadata(memory)

        try:
            # Check if memory already exists in collection
            try:
                existing = collection.get(ids=[mem_id], include=[])
                existing_ids = existing.get("ids", []) if existing else []
            except Exception:
                existing_ids = []

            if existing_ids:
                # Update existing memory
                collection.update(
                    ids=[mem_id],
                    documents=[content],
                    metadatas=[meta],
                )
            else:
                # Add new memory
                collection.add(
                    ids=[mem_id],
                    documents=[content],
                    metadatas=[meta],
                )

            synced[mem_id] = content_hash
            summary["writesSucceeded"] += 1

        except Exception as exc:
            summary["writesFailed"] += 1
            summary["errors"].append({
                "memoryId": mem_id,
                "error": str(exc),
            })
            if args.strict:
                break

    # Update state
    state["syncedReverse"] = synced
    state["lastRunReverseUtc"] = datetime.now(timezone.utc).isoformat()
    state["lastSummaryReverse"] = {
        "seen": summary["seen"],
        "candidateWrites": summary["candidateWrites"],
        "writesSucceeded": summary["writesSucceeded"],
        "writesFailed": summary["writesFailed"],
        "skippedUnchanged": summary["skippedUnchanged"],
        "mode": summary["mode"],
    }
    
    if not args.dry_run:
        _save_json(args.state_file, state)

    # Append history entry
    history_entry = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "seen": summary["seen"],
        "writes": summary["writesSucceeded"],
        "failed": summary["writesFailed"],
        "skipped": summary["skippedUnchanged"],
        "mode": summary["mode"],
    }
    _append_history(args.history_file, history_entry, args.history_max_entries)

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
