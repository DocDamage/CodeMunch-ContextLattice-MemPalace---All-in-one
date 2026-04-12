#!/usr/bin/env python3
"""Incremental one-way bridge: MemPalace -> ContextLattice (Multi-Palace support)."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import PurePath
from typing import Any
from urllib import error, request

import chromadb


# Retry configuration
DEFAULT_MAX_RETRIES = 3
DEFAULT_RETRY_DELAY = 1.0  # seconds
RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}
DEFAULT_WORKERS = 4
MAX_WORKERS_LIMIT = 10


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


def _is_retryable_error(exc: Exception) -> bool:
    """Determine if an exception is retryable (transient network/server error)."""
    # HTTP errors with specific status codes
    if isinstance(exc, error.HTTPError):
        return exc.code in RETRYABLE_STATUS_CODES
    # Network-level errors
    if isinstance(exc, (error.URLError, TimeoutError)):
        return True
    # Connection-related errors
    if isinstance(exc, OSError) and hasattr(exc, 'errno'):
        # ECONNREFUSED, ECONNRESET, ETIMEDOUT, etc.
        if exc.errno in (54, 61, 60, 65):  # Connection reset, refused, timeout, no route
            return True
    return False


def _post_json_with_retry(
    url: str,
    api_key: str,
    payload: dict[str, Any],
    timeout: int = 30,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_delay: float = DEFAULT_RETRY_DELAY,
) -> dict[str, Any]:
    """POST JSON with exponential backoff retry logic."""
    body = json.dumps(payload).encode("utf-8")
    last_exception: Exception | None = None
    
    for attempt in range(max_retries + 1):
        try:
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
        except Exception as exc:
            last_exception = exc
            
            # Don't retry on last attempt
            if attempt >= max_retries:
                break
            
            # Don't retry non-retryable errors (like 400 Bad Request)
            if not _is_retryable_error(exc):
                raise
            
            # Calculate exponential backoff delay: delay * 2^attempt
            sleep_time = retry_delay * (2 ** attempt)
            time.sleep(sleep_time)
    
    # All retries exhausted
    if last_exception:
        raise last_exception
    return {}


def _post_json(url: str, api_key: str, payload: dict[str, Any], timeout: int = 30) -> dict[str, Any]:
    """POST JSON with default retry configuration."""
    return _post_json_with_retry(url, api_key, payload, timeout=timeout)


def _get_json_with_retry(
    url: str,
    api_key: str,
    timeout: int = 15,
    max_retries: int = DEFAULT_MAX_RETRIES,
    retry_delay: float = DEFAULT_RETRY_DELAY,
) -> dict[str, Any]:
    """GET JSON with exponential backoff retry logic."""
    last_exception: Exception | None = None
    
    for attempt in range(max_retries + 1):
        try:
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
        except Exception as exc:
            last_exception = exc
            
            # Don't retry on last attempt
            if attempt >= max_retries:
                break
            
            # Don't retry non-retryable errors
            if not _is_retryable_error(exc):
                raise
            
            # Exponential backoff
            sleep_time = retry_delay * (2 ** attempt)
            time.sleep(sleep_time)
    
    # All retries exhausted
    if last_exception:
        raise last_exception
    return {}


def _get_json(url: str, api_key: str, timeout: int = 15) -> dict[str, Any]:
    """GET JSON with default retry configuration."""
    return _get_json_with_retry(url, api_key, timeout=timeout)


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
                lines = lines[-max_entries:]
                with open(history_path, "w", encoding="utf-8") as f:
                    f.writelines(lines)
        except Exception:
            pass


def cosine_similarity(a: list[float], b: list[float]) -> float:
    """Calculate cosine similarity between two vectors."""
    if len(a) != len(b):
        return 0.0
    dot_product = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot_product / (norm_a * norm_b)


def _get_embedding_function() -> Any:
    """Get embedding function using ChromaDB's default embedding function."""
    try:
        from chromadb.utils.embedding_functions import DefaultEmbeddingFunction
        return DefaultEmbeddingFunction()
    except Exception:
        return None


def _generate_embedding(text: str, embedding_fn: Any) -> list[float] | None:
    """Generate embedding for text using the provided embedding function."""
    if embedding_fn is None:
        return None
    try:
        result = embedding_fn([text])
        if result and len(result) > 0:
            embedding = result[0]
            if isinstance(embedding, list):
                return embedding
        return None
    except Exception:
        return None


def _is_content_changed(
    drawer_id: str,
    content_hash: str,
    new_embedding: list[float] | None,
    synced: dict[str, Any],
    semantic_diff: bool,
    similarity_threshold: float,
) -> bool:
    """Determine if content has changed using hash or semantic comparison."""
    synced_entry = synced.get(drawer_id)
    
    if synced_entry is None:
        return True
    
    if isinstance(synced_entry, str):
        return synced_entry != content_hash
    
    if isinstance(synced_entry, dict):
        stored_hash = synced_entry.get("hash", "")
        
        if semantic_diff and new_embedding is not None:
            stored_embedding = synced_entry.get("embedding")
            if stored_embedding is not None:
                similarity = cosine_similarity(new_embedding, stored_embedding)
                return similarity < similarity_threshold
            return stored_hash != content_hash
        
        return stored_hash != content_hash
    
    return True


class SyncStateManager:
    """Thread-safe manager for sync state and summary updates."""
    
    def __init__(self, synced: dict[str, Any], summary: dict[str, Any]):
        self.synced = synced
        self.summary = summary
        self._lock = threading.Lock()
    
    def record_success(self, drawer_id: str, content_hash: str, embedding: list[float] | None) -> None:
        """Thread-safe update for successful write."""
        with self._lock:
            self.synced[drawer_id] = {
                "hash": content_hash,
                "embedding": embedding,
                "lastSync": datetime.now(timezone.utc).isoformat(),
            }
            self.summary["writesSucceeded"] += 1
    
    def record_failure(self, drawer_id: str, error_msg: str) -> None:
        """Thread-safe update for failed write."""
        with self._lock:
            self.summary["writesFailed"] += 1
            self.summary["errors"].append({
                "drawerId": drawer_id,
                "error": error_msg,
            })


def _write_single_drawer(
    drawer_data: tuple[str, str, dict[str, Any], list[float] | None, str],
    orchestrator_url: str,
    api_key: str,
    state_manager: SyncStateManager,
    max_retries: int,
    retry_delay: float,
) -> tuple[str, bool, str | None]:
    """Write a single drawer to ContextLattice."""
    drawer_id, doc, meta, embedding, content_hash = drawer_data
    
    wing = _as_text(meta.get("wing", "general"))
    room = _as_text(meta.get("room", "general"))
    source_file = _as_text(meta.get("source_file", "source"))
    source_stem = _slug(PurePath(source_file).stem or "source")
    wing_slug = _slug(wing)
    room_slug = _slug(room)
    
    project_name = _as_text(meta.get("project", "default_project"))
    topic_prefix = _as_text(meta.get("topic_prefix", "mempalace"))
    
    topic_path = "/".join([_slug(topic_prefix, "mempalace"), wing_slug, room_slug])
    file_name = f"mempalace/{wing_slug}/{room_slug}/{_slug(drawer_id)}-{source_stem}.md"
    
    payload = {
        "projectName": project_name,
        "fileName": file_name,
        "content": doc,
        "topicPath": topic_path,
    }
    
    try:
        result = _post_json_with_retry(
            f"{orchestrator_url}/memory/write",
            api_key,
            payload,
            max_retries=max_retries,
            retry_delay=retry_delay,
        )
        if isinstance(result, dict) and result.get("ok") is False:
            raise RuntimeError(f"memory/write returned ok=false: {result}")
        
        state_manager.record_success(drawer_id, content_hash, embedding)
        return (drawer_id, True, None)
    except Exception as exc:
        error_msg = str(exc)
        state_manager.record_failure(drawer_id, error_msg)
        return (drawer_id, False, error_msg)


def _process_writes_parallel(
    write_candidates: list[tuple[str, str, dict[str, Any], list[float] | None, str]],
    orchestrator_url: str,
    api_key: str,
    state_manager: SyncStateManager,
    max_retries: int,
    retry_delay: float,
    workers: int,
    strict: bool,
) -> bool:
    """Process writes in parallel using ThreadPoolExecutor."""
    completed = 0
    total = len(write_candidates)
    should_stop = False
    
    with ThreadPoolExecutor(max_workers=workers, thread_name_prefix="sync_worker") as executor:
        future_to_drawer = {
            executor.submit(
                _write_single_drawer,
                candidate,
                orchestrator_url,
                api_key,
                state_manager,
                max_retries,
                retry_delay,
            ): candidate[0]
            for candidate in write_candidates
        }
        
        for future in as_completed(future_to_drawer):
            drawer_id = future_to_drawer[future]
            completed += 1
            
            if completed % 10 == 0 or completed == total:
                print(
                    f"Progress: {completed}/{total} writes completed "
                    f"({state_manager.summary['writesSucceeded']} succeeded, "
                    f"{state_manager.summary['writesFailed']} failed)",
                    file=sys.stderr,
                )
            
            try:
                drawer_id, success, error_msg = future.result()
                
                if not success and strict:
                    should_stop = True
                    for f in future_to_drawer:
                        f.cancel()
                    break
            except Exception as exc:
                state_manager.record_failure(drawer_id, f"Unexpected error: {exc}")
                if strict:
                    should_stop = True
                    for f in future_to_drawer:
                        f.cancel()
                    break
    
    return not should_stop


# Multi-palace configuration handling

PalaceConfig = dict[str, Any]


def _is_legacy_config(config: dict[str, Any]) -> bool:
    """Check if config is in legacy single-palace format."""
    # Legacy format has palacePath, collectionName directly at root
    # New format has "palaces" array
    if "palaces" in config:
        return False
    if "palacePath" in config or "collectionName" in config:
        return True
    return False


def _migrate_config(
    config: dict[str, Any],
    config_path: str,
) -> dict[str, Any]:
    """Migrate legacy config to multi-palace format."""
    new_config = {
        "version": "2.0",
        "palaces": [
            {
                "path": config.get("palacePath", "~/.mempalace/palace"),
                "collectionName": config.get("collectionName", "mempalace_drawers"),
                "topicPrefix": config.get("topicPrefix", "mempalace"),
                "wingProjectMap": config.get("wingProjectMap", {}),
            }
        ],
    }
    
    # Copy global settings
    if "orchestratorUrl" in config:
        new_config["orchestratorUrl"] = config["orchestratorUrl"]
    if "apiKeyEnvVar" in config:
        new_config["apiKeyEnvVar"] = config["apiKeyEnvVar"]
    if "defaultProjectName" in config:
        new_config["defaultProjectName"] = config["defaultProjectName"]
    
    return new_config


def _backup_and_migrate_config(config_path: str) -> dict[str, Any] | None:
    """Backup old config and migrate to new format. Returns migrated config or None."""
    if not os.path.exists(config_path):
        return None
    
    config = _load_json(config_path)
    if not _is_legacy_config(config):
        return None
    
    # Backup old config
    backup_path = config_path + ".legacy-backup"
    try:
        shutil.copy2(config_path, backup_path)
        print(f"Backed up legacy config to: {backup_path}", file=sys.stderr)
    except Exception as exc:
        print(f"Warning: Could not backup config: {exc}", file=sys.stderr)
    
    # Migrate
    new_config = _migrate_config(config, config_path)
    
    try:
        _save_json(config_path, new_config)
        print(f"Migrated config to multi-palace format (version 2.0)", file=sys.stderr)
    except Exception as exc:
        print(f"Warning: Could not save migrated config: {exc}", file=sys.stderr)
        return None
    
    return new_config


def _load_palace_configs(config_path: str) -> list[PalaceConfig]:
    """Load palace configs from file, handling migration."""
    config = _load_json(config_path)
    
    # Check if migration is needed
    if _is_legacy_config(config):
        migrated = _backup_and_migrate_config(config_path)
        if migrated:
            config = migrated
    
    # Extract palace list
    if "palaces" in config and isinstance(config["palaces"], list):
        palaces = []
        for idx, palace in enumerate(config["palaces"]):
            if isinstance(palace, dict):
                palaces.append({
                    "id": f"palace_{idx}",
                    "path": os.path.expanduser(palace.get("path", "~/.mempalace/palace")),
                    "collectionName": palace.get("collectionName", "mempalace_drawers"),
                    "topicPrefix": palace.get("topicPrefix", "mempalace"),
                    "wingProjectMap": _extract_wing_map(palace),
                })
        return palaces
    
    # Fallback: return single default palace
    return [{
        "id": "palace_0",
        "path": os.path.expanduser("~/.mempalace/palace"),
        "collectionName": "mempalace_drawers",
        "topicPrefix": "mempalace",
        "wingProjectMap": {},
    }]


def _get_global_config(config_path: str) -> dict[str, Any]:
    """Get global config values (orchestratorUrl, apiKeyEnvVar, etc.)."""
    config = _load_json(config_path)
    return {
        "orchestratorUrl": config.get("orchestratorUrl", ""),
        "apiKeyEnvVar": config.get("apiKeyEnvVar", ""),
        "defaultProjectName": config.get("defaultProjectName", ""),
    }


def _load_sync_state(state_path: str) -> dict[str, Any]:
    """Load sync state, handling version migration."""
    state = _load_json(state_path)
    
    if not state:
        return {"version": 2, "palaces": {}}
    
    # Check if legacy format (version 1 or no version)
    current_version = state.get("version", 1)
    if current_version < 2:
        # Migrate from version 1 to version 2
        new_state = {
            "version": 2,
            "palaces": {
                "palace_0": {
                    "synced": state.get("synced", {}),
                    "lastRunUtc": state.get("lastRunUtc", ""),
                }
            },
        }
        if "lastSummary" in state:
            new_state["lastSummary"] = state["lastSummary"]
        return new_state
    
    return state


def _save_sync_state(state_path: str, state: dict[str, Any]) -> None:
    """Save sync state."""
    _save_json(state_path, state)


def _sync_single_palace(
    palace: PalaceConfig,
    orchestrator_url: str,
    api_key: str,
    default_project: str,
    args: argparse.Namespace,
    embedding_fn: Any,
    state: dict[str, Any],
) -> dict[str, Any]:
    """Sync a single palace. Returns palace summary."""
    palace_id = palace["id"]
    palace_path = palace["path"]
    collection_name = palace["collectionName"]
    topic_prefix = palace["topicPrefix"]
    wing_project_map = palace["wingProjectMap"]
    
    summary = {
        "palaceId": palace_id,
        "palacePath": palace_path,
        "collectionName": collection_name,
        "topicPrefix": topic_prefix,
        "mode": "dry_run" if args.dry_run else "write",
        "seen": 0,
        "candidateWrites": 0,
        "writesSucceeded": 0,
        "writesFailed": 0,
        "skippedUnchanged": 0,
        "errors": [],
    }
    
    if not os.path.isdir(palace_path):
        summary["errors"].append(f"Palace path does not exist: {palace_path}")
        return summary
    
    try:
        client = chromadb.PersistentClient(path=palace_path)
        collection = client.get_collection(collection_name)
    except Exception as exc:
        msg = str(exc).lower()
        if "does not exist" in msg or "not found" in msg:
            summary["note"] = f"Collection '{collection_name}' does not exist yet."
            return summary
        summary["errors"].append(f"Could not open collection '{collection_name}': {exc}")
        return summary
    
    # Get per-palace synced state
    palace_state = state.get("palaces", {}).get(palace_id, {})
    synced: dict[str, Any] = palace_state.get("synced", {}) if isinstance(palace_state.get("synced"), dict) else {}
    
    # Create state manager
    state_manager = SyncStateManager(synced, summary)
    
    processed_writes = 0
    offset = 0
    stop = False
    write_candidates: list[tuple[str, str, dict[str, Any], list[float] | None, str]] = []
    
    # Phase 1: Collect all write candidates
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
            
            embedding: list[float] | None = None
            if args.semantic_diff and embedding_fn is not None:
                embedding = _generate_embedding(doc, embedding_fn)
            
            is_changed = _is_content_changed(
                drawer_id,
                content_hash,
                embedding,
                synced,
                args.semantic_diff,
                args.similarity_threshold,
            )
            
            if not args.force_resync and not is_changed:
                summary["skippedUnchanged"] += 1
                continue
            
            if args.limit > 0 and processed_writes >= args.limit:
                stop = True
                break
            
            wing = _as_text(meta.get("wing", "general"))
            room = _as_text(meta.get("room", "general"))
            source_file = _as_text(meta.get("source_file", "source"))
            
            project_name = wing_project_map.get(wing) or default_project
            
            worker_meta = dict(meta)
            worker_meta["project"] = project_name
            worker_meta["topic_prefix"] = topic_prefix
            worker_meta["wing"] = wing
            worker_meta["room"] = room
            worker_meta["source_file"] = source_file
            
            write_candidates.append((drawer_id, doc, worker_meta, embedding, content_hash))
            
            summary["candidateWrites"] += 1
            processed_writes += 1
            
            if args.dry_run:
                continue
            
            if args.workers == 1:
                wing_slug = _slug(wing)
                room_slug = _slug(room)
                source_stem = _slug(PurePath(source_file).stem or "source")
                
                topic_path = "/".join([_slug(topic_prefix, "mempalace"), wing_slug, room_slug])
                file_name = f"mempalace/{wing_slug}/{room_slug}/{_slug(drawer_id)}-{source_stem}.md"
                
                payload = {
                    "projectName": project_name,
                    "fileName": file_name,
                    "content": doc,
                    "topicPath": topic_path,
                }
                
                try:
                    result = _post_json_with_retry(
                        f"{orchestrator_url}/memory/write",
                        api_key,
                        payload,
                        max_retries=args.max_retries,
                        retry_delay=args.retry_delay,
                    )
                    if isinstance(result, dict) and result.get("ok") is False:
                        raise RuntimeError(f"memory/write returned ok=false: {result}")
                    
                    state_manager.record_success(drawer_id, content_hash, embedding)
                except Exception as exc:
                    state_manager.record_failure(drawer_id, str(exc))
                    if args.strict:
                        stop = True
                        break
        
        offset += len(ids)
    
    # Phase 2: Process writes in parallel
    if not args.dry_run and args.workers > 1 and write_candidates:
        print(
            f"[{palace_id}] Processing {len(write_candidates)} writes with {args.workers} workers...",
            file=sys.stderr,
        )
        
        _process_writes_parallel(
            write_candidates,
            orchestrator_url,
            api_key,
            state_manager,
            args.max_retries,
            args.retry_delay,
            args.workers,
            args.strict,
        )
    
    # Update state for this palace
    if "palaces" not in state:
        state["palaces"] = {}
    state["palaces"][palace_id] = {
        "synced": synced,
        "lastRunUtc": datetime.now(timezone.utc).isoformat(),
    }
    
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync MemPalace drawers into ContextLattice (Multi-Palace)")
    parser.add_argument("--config-file", default=".memorybridge/bridge.config.json")
    parser.add_argument("--state-file", default=".memorybridge/sync-state.json")
    parser.add_argument("--history-file", default=".memorybridge/sync-history.jsonl")
    parser.add_argument("--history-max-entries", type=int, default=500)
    parser.add_argument("--orchestrator-url", default="")
    parser.add_argument("--api-key", default="")
    parser.add_argument("--api-key-env-var", default="")
    parser.add_argument("--palace-path", default="")  # CLI override for single palace
    parser.add_argument("--collection-name", default="")  # CLI override
    parser.add_argument("--default-project-name", default="")
    parser.add_argument("--topic-prefix", default="")  # CLI override
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-resync", action="store_true")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--semantic-diff", action="store_true")
    parser.add_argument("--similarity-threshold", type=float, default=0.95)
    parser.add_argument("--max-retries", type=int, default=DEFAULT_MAX_RETRIES)
    parser.add_argument("--retry-delay", type=float, default=DEFAULT_RETRY_DELAY)
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help=f"Number of parallel workers for writes (default: {DEFAULT_WORKERS}, max: {MAX_WORKERS_LIMIT})",
    )
    parser.add_argument("--palace-index", type=int, default=-1, help="Sync only specific palace by index (0-based)")
    args = parser.parse_args()
    
    # Validate workers
    if args.workers < 1:
        print(json.dumps({"error": "--workers must be >= 1"}))
        return 2
    if args.workers > MAX_WORKERS_LIMIT:
        print(json.dumps({"error": f"--workers cannot exceed {MAX_WORKERS_LIMIT}"}))
        return 2
    
    # Load global config
    global_config = _get_global_config(args.config_file)
    
    # Load palace configurations
    if args.palace_path:
        # CLI override: use single palace
        palaces = [{
            "id": "palace_0",
            "path": os.path.expanduser(args.palace_path),
            "collectionName": args.collection_name or "mempalace_drawers",
            "topicPrefix": args.topic_prefix or "mempalace",
            "wingProjectMap": {},
        }]
    else:
        palaces = _load_palace_configs(args.config_file)
    
    # Filter by palace-index if specified
    if args.palace_index >= 0:
        if args.palace_index >= len(palaces):
            print(json.dumps({"error": f"--palace-index {args.palace_index} out of range (0-{len(palaces)-1})"}))
            return 2
        palaces = [palaces[args.palace_index]]
    
    # Resolve API key and orchestrator URL
    api_key_env_var = _resolve(
        "api_key_env_var",
        args.api_key_env_var,
        global_config.get("apiKeyEnvVar", ""),
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
        global_config.get("orchestratorUrl", ""),
        os.environ.get("CONTEXTLATTICE_ORCHESTRATOR_URL", ""),
        "http://127.0.0.1:8075",
    ).rstrip("/")
    default_project = _resolve(
        "default_project",
        args.default_project_name,
        global_config.get("defaultProjectName", ""),
        "",
        "default_project",
    )
    
    if not args.dry_run and not api_key:
        print(json.dumps({"error": f"Missing API key. Set --api-key or env var {api_key_env_var}."}))
        return 2
    
    if args.batch_size <= 0:
        print(json.dumps({"error": "--batch-size must be > 0"}))
        return 2
    
    # Health check
    if not args.dry_run:
        try:
            _ = _get_json_with_retry(
                f"{orchestrator_url}/status",
                api_key,
                max_retries=args.max_retries,
                retry_delay=args.retry_delay,
            )
        except Exception as exc:
            print(json.dumps({"error": f"ContextLattice status check failed: {exc}"}))
            return 2
    
    # Initialize embedding function if semantic diff is enabled
    embedding_fn = None
    if args.semantic_diff:
        embedding_fn = _get_embedding_function()
        if embedding_fn is None:
            print(json.dumps({"warning": "Semantic diff requested but embedding function unavailable. Falling back to hash comparison."}))
    
    # Load sync state
    state = _load_sync_state(args.state_file)
    
    # Process each palace
    palace_summaries: list[dict[str, Any]] = []
    total_errors: list[dict[str, Any]] = []
    
    for palace in palaces:
        print(f"Syncing palace: {palace['id']} ({palace['path']})", file=sys.stderr)
        
        try:
            summary = _sync_single_palace(
                palace,
                orchestrator_url,
                api_key,
                default_project,
                args,
                embedding_fn,
                state,
            )
            palace_summaries.append(summary)
            total_errors.extend(summary.get("errors", []))
        except Exception as exc:
            error_entry = {
                "palaceId": palace["id"],
                "error": str(exc),
            }
            total_errors.append(error_entry)
            palace_summaries.append({
                "palaceId": palace["id"],
                "palacePath": palace["path"],
                "error": str(exc),
            })
            if args.strict:
                print(f"Stopping due to error in strict mode: {exc}", file=sys.stderr)
                break
    
    # Update last summary in state
    total_seen = sum(s.get("seen", 0) for s in palace_summaries)
    total_candidate = sum(s.get("candidateWrites", 0) for s in palace_summaries)
    total_succeeded = sum(s.get("writesSucceeded", 0) for s in palace_summaries)
    total_failed = sum(s.get("writesFailed", 0) for s in palace_summaries)
    total_skipped = sum(s.get("skippedUnchanged", 0) for s in palace_summaries)
    
    state["lastSummary"] = {
        "palaceCount": len(palaces),
        "processedCount": len(palace_summaries),
        "seen": total_seen,
        "candidateWrites": total_candidate,
        "writesSucceeded": total_succeeded,
        "writesFailed": total_failed,
        "skippedUnchanged": total_skipped,
        "mode": "dry_run" if args.dry_run else "write",
        "workers": args.workers,
        "errors": total_errors,
    }
    
    if not args.dry_run:
        _save_sync_state(args.state_file, state)
    
    # Append history entry
    history_entry = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "palaceCount": len(palaces),
        "seen": total_seen,
        "writes": total_succeeded,
        "failed": total_failed,
        "skipped": total_skipped,
        "mode": "dry_run" if args.dry_run else "write",
        "workers": args.workers,
    }
    _append_history(args.history_file, history_entry, args.history_max_entries)
    
    # Build consolidated summary
    consolidated = {
        "mode": "dry_run" if args.dry_run else "write",
        "orchestratorUrl": orchestrator_url,
        "palaceCount": len(palaces),
        "processedCount": len(palace_summaries),
        "seen": total_seen,
        "candidateWrites": total_candidate,
        "writesSucceeded": total_succeeded,
        "writesFailed": total_failed,
        "skippedUnchanged": total_skipped,
        "semanticDiff": args.semantic_diff,
        "similarityThreshold": args.similarity_threshold,
        "maxRetries": args.max_retries,
        "retryDelay": args.retry_delay,
        "workers": args.workers,
        "palaces": palace_summaries,
        "errors": total_errors,
    }
    
    print(json.dumps(consolidated, indent=2))
    return 0 if total_failed == 0 else 3


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
