#!/usr/bin/env python3
"""LensCloud Bench Command runner.

This runner intentionally avoids Kubernetes API access. It reads one approved
request JSON file, operates only on the mounted Bench/Site filesystem, and
writes a sanitized JSON summary to the container termination log.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


COMMANDS = {
    "backup.create",
    "backup.status",
    "restore.preview",
    "restore.execute",
    "restore.status",
    "maintenance_mode.enable",
    "maintenance_mode.disable",
    "maintenance_mode.status",
    "developer_mode.enable",
    "developer_mode.disable",
    "developer_mode.status",
    "site_config.set",
    "site_config.unset",
    "site_config.get",
    "cors.allowlist.update",
    "cors.allowlist.get",
    "bench_test.trigger",
    "bench_test.status",
    "latp.trigger",
    "latp.status",
}

RUNNER_PENDING = {
    "backup.create",
    "backup.status",
    "restore.preview",
    "restore.execute",
    "restore.status",
    "bench_test.trigger",
    "latp.trigger",
    "latp.status",
}

APPROVED_SITE_CONFIG_KEYS = {
    item.strip()
    for item in os.environ.get(
        "LENS_COMMAND_ALLOWED_SITE_CONFIG_KEYS",
        "maintenance_mode,developer_mode,allow_cors,server_script_enabled,client_script_enabled",
    ).split(",")
    if item.strip()
}

SENSITIVE_KEY_RE = re.compile(
    r"(password|passwd|secret|token|api[_-]?key|private[_-]?key|credential|cookie|authorization)",
    re.IGNORECASE,
)
SITE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,190}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,190}$")


class CommandError(Exception):
    def __init__(self, code: str, message: str, phase: str = "Failed") -> None:
        super().__init__(message)
        self.code = code
        self.phase = phase
        self.message = message


def getenv_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).resolve()


REQUEST_PATH = getenv_path("BENCH_COMMAND_REQUEST", "/lenscloud/request/request.json")
BENCH_PATH = getenv_path("BENCH_PATH", "/home/frappe/frappe-bench")
SITES_PATH = getenv_path("BENCH_SITES_PATH", str(BENCH_PATH / "sites"))
TERMINATION_PATH = Path(os.environ.get("BENCH_COMMAND_TERMINATION_LOG", "/dev/termination-log"))


def sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            if SENSITIVE_KEY_RE.search(str(key)):
                redacted[key] = "[REDACTED]"
            else:
                redacted[key] = sanitize(item)
        return redacted
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, str) and (
        "-----BEGIN " in value
        or "password=" in value.lower()
        or "token=" in value.lower()
    ):
        return "[REDACTED]"
    return value


def result(
    *,
    phase: str,
    command: str,
    target: dict[str, Any],
    summary: str,
    changed: bool = False,
    code: str | None = None,
    details: dict[str, Any] | None = None,
    display: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = {
        "phase": phase,
        "commandId": current_request.get("commandId"),
        "command": command,
        "target": {
            "namespace": target.get("namespace"),
            "bench": target.get("bench"),
            "site": target.get("site"),
        },
        "summary": summary,
        "changed": changed,
        "redacted": True,
    }
    if code:
        payload["code"] = code
    if details:
        payload["details"] = sanitize(details)
    if display:
        payload["display"] = sanitize(display)
    return payload


def human_flag(value: Any) -> str:
    return "On" if bool(int(value or 0)) else "Off"


def scalar_kind(value: Any) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if value is None:
        return "empty"
    return "string"


def site_config_label(key: str) -> str:
    labels = {
        "allow_cors": "CORS allowlist",
        "client_script_enabled": "Client script",
        "developer_mode": "Developer mode",
        "maintenance_mode": "Maintenance mode",
        "server_script_enabled": "Server script",
    }
    return labels.get(key, f"Site config: {key}")


def display_for_site_config(key: str, value: Any) -> dict[str, Any]:
    if key in {"maintenance_mode", "developer_mode", "server_script_enabled", "client_script_enabled"}:
        raw_value = int(value or 0)
        return {
            "label": site_config_label(key),
            "value": human_flag(raw_value),
            "kind": "boolean",
            "rawValue": raw_value,
            "safe": True,
        }
    if key == "allow_cors":
        origins = [item for item in str(value or "").splitlines() if item.strip()]
        return {
            "label": site_config_label(key),
            "value": origins,
            "kind": "origin-list",
            "rawValue": origins,
            "safe": True,
        }
    return {
        "label": site_config_label(key),
        "value": "" if value is None else str(value),
        "kind": scalar_kind(value),
        "rawValue": value,
        "safe": True,
    }


def write_result(payload: dict[str, Any]) -> None:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    TERMINATION_PATH.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)


def read_request() -> dict[str, Any]:
    if not REQUEST_PATH.is_file():
        raise CommandError("INVALID_ARGUMENTS", "request.json is not mounted")
    try:
        data = json.loads(REQUEST_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise CommandError("INVALID_ARGUMENTS", "request.json is invalid JSON") from exc
    if not isinstance(data, dict):
        raise CommandError("INVALID_ARGUMENTS", "request.json must be an object")
    return data


def validate_request(req: dict[str, Any]) -> tuple[str, dict[str, Any], dict[str, Any]]:
    command = req.get("command")
    if command not in COMMANDS:
        raise CommandError("COMMAND_UNSUPPORTED", "command is not in the runner allowlist", "Unsupported")

    target = req.get("target")
    if not isinstance(target, dict):
        raise CommandError("INVALID_ARGUMENTS", "target must be an object")

    namespace = str(target.get("namespace") or "")
    bench = str(target.get("bench") or "")
    site = str(target.get("site") or "")
    if not NAME_RE.match(namespace):
        raise CommandError("NAMESPACE_NOT_APPROVED", "target namespace is invalid")
    if not NAME_RE.match(bench):
        raise CommandError("TARGET_NOT_FOUND", "target bench is invalid")
    if not SITE_RE.match(site) or ".." in site or "/" in site:
        raise CommandError("TARGET_NOT_FOUND", "target site is invalid")

    args = req.get("args") or {}
    if not isinstance(args, dict):
        raise CommandError("INVALID_ARGUMENTS", "args must be an object")
    return command, target, args


def candidate_site_roots(site: str) -> list[tuple[str, Path]]:
    return [
        ("sites-root", SITES_PATH / site),
        ("frappe-sites", SITES_PATH / "frappe-sites" / site),
    ]


def site_config_path(site: str) -> tuple[Path, str]:
    expected_root = SITES_PATH.resolve()
    matches: list[tuple[str, Path]] = []
    for layout, site_root in candidate_site_roots(site):
        path = (site_root / "site_config.json").resolve()
        if expected_root not in path.parents:
            raise CommandError("TARGET_MISMATCH", "site path escapes bench sites directory")
        if path.is_file():
            matches.append((layout, path))
    if len(matches) > 1:
        raise CommandError("TARGET_MISMATCH", "site_config.json matched multiple supported layouts")
    if not matches:
        raise CommandError("TARGET_NOT_FOUND", "site_config.json was not found")
    layout, path = matches[0]
    if expected_root not in path.parents:
        raise CommandError("TARGET_MISMATCH", "site path escapes bench sites directory")
    return path, layout


def load_site_config(site: str) -> tuple[Path, str, dict[str, Any]]:
    path, layout = site_config_path(site)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise CommandError("RUNNER_FAILED", "site_config.json is invalid JSON") from exc
    if not isinstance(data, dict):
        raise CommandError("RUNNER_FAILED", "site_config.json must be an object")
    return path, layout, data


def write_site_config(path: Path, data: dict[str, Any]) -> None:
    sanitized_data = dict(data)
    fd, temp_name = tempfile.mkstemp(prefix=".site_config.", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(sanitized_data, handle, indent=1, sort_keys=True)
            handle.write("\n")
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def ensure_key_allowed(key: str) -> None:
    if SENSITIVE_KEY_RE.search(key):
        raise CommandError("INVALID_ARGUMENTS", "site_config key is not approved")
    if key not in APPROVED_SITE_CONFIG_KEYS:
        raise CommandError("INVALID_ARGUMENTS", "site_config key is not approved")


def command_site_config(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    path, layout, config = load_site_config(site)

    if command == "site_config.get":
        key = str(args.get("key") or "")
        ensure_key_allowed(key)
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary=f"Read approved site_config key {key}",
            details={"key": key, "value": config.get(key), "layout": layout},
            display=display_for_site_config(key, config.get(key)),
        )

    if command == "site_config.set":
        key = str(args.get("key") or "")
        ensure_key_allowed(key)
        if "value" not in args:
            raise CommandError("INVALID_ARGUMENTS", "site_config.set requires value")
        value = args["value"]
        if isinstance(value, (dict, list)):
            raise CommandError("INVALID_ARGUMENTS", "site_config value must be scalar")
        before = config.get(key)
        config[key] = value
        write_site_config(path, config)
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary=f"Set approved site_config key {key}",
            changed=before != value,
            details={"key": key, "value": value, "layout": layout},
        )

    if command == "site_config.unset":
        key = str(args.get("key") or "")
        ensure_key_allowed(key)
        existed = key in config
        config.pop(key, None)
        write_site_config(path, config)
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary=f"Unset approved site_config key {key}",
            changed=existed,
            details={"key": key, "layout": layout},
        )

    raise CommandError("COMMAND_UNSUPPORTED", "unsupported site_config command", "Unsupported")


def command_boolean_config(
    command: str,
    target: dict[str, Any],
    key: str,
    value: int | None,
) -> dict[str, Any]:
    site = str(target["site"])
    path, layout, config = load_site_config(site)
    ensure_key_allowed(key)

    if command.endswith(".status"):
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary=f"Read {key} status",
            details={"key": key, "value": int(config.get(key) or 0), "layout": layout},
            display=display_for_site_config(key, int(config.get(key) or 0)),
        )

    before = int(config.get(key) or 0)
    config[key] = int(value or 0)
    write_site_config(path, config)
    return result(
        phase="Succeeded",
        command=command,
        target=target,
        summary=f"Set {key} to {int(value or 0)}",
        changed=before != int(value or 0),
        details={"key": key, "value": int(value or 0), "layout": layout},
    )


def command_cors(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    path, layout, config = load_site_config(site)
    key = "allow_cors"
    ensure_key_allowed(key)
    if command == "cors.allowlist.get":
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary="Read CORS allowlist",
            details={"key": key, "value": config.get(key), "layout": layout},
            display=display_for_site_config(key, config.get(key)),
        )
    origins = args.get("origins")
    if not isinstance(origins, list) or not all(isinstance(item, str) for item in origins):
        raise CommandError("INVALID_ARGUMENTS", "cors.allowlist.update requires string list origins")
    if any(item.strip() == "*" for item in origins):
        raise CommandError("INVALID_ARGUMENTS", "wildcard CORS origin is not allowed")
    normalized = "\n".join(sorted({item.strip() for item in origins if item.strip()}))
    before = config.get(key)
    config[key] = normalized
    write_site_config(path, config)
    return result(
        phase="Succeeded",
        command=command,
        target=target,
        summary="Updated CORS allowlist",
        changed=before != normalized,
        details={"key": key, "origins": normalized.splitlines(), "layout": layout},
    )


def dispatch(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    if command in RUNNER_PENDING:
        raise CommandError("COMMAND_UNSUPPORTED", "command family is contracted but runner-pending", "Unsupported")
    if command.startswith("site_config."):
        return command_site_config(command, target, args)
    if command.startswith("maintenance_mode."):
        value = 1 if command.endswith(".enable") else 0
        return command_boolean_config(command, target, "maintenance_mode", None if command.endswith(".status") else value)
    if command.startswith("developer_mode."):
        value = 1 if command.endswith(".enable") else 0
        return command_boolean_config(command, target, "developer_mode", None if command.endswith(".status") else value)
    if command.startswith("cors."):
        return command_cors(command, target, args)
    raise CommandError("COMMAND_UNSUPPORTED", "command is contracted but not implemented", "Unsupported")


current_request: dict[str, Any] = {}


def main() -> int:
    global current_request
    try:
        current_request = read_request()
        command, target, args = validate_request(current_request)
        payload = dispatch(command, target, args)
        write_result(payload)
        return 0 if payload["phase"] == "Succeeded" else 2
    except CommandError as exc:
        target = current_request.get("target") if isinstance(current_request.get("target"), dict) else {}
        command = str(current_request.get("command") or "unknown")
        payload = result(
            phase=exc.phase,
            command=command,
            target=target,
            summary=exc.message,
            code=exc.code,
        )
        write_result(payload)
        return 0 if exc.phase == "Unsupported" else 1
    except Exception:
        payload = result(
            phase="Failed",
            command=str(current_request.get("command") or "unknown"),
            target=current_request.get("target") if isinstance(current_request.get("target"), dict) else {},
            summary="Runner failed with sanitized internal error",
            code="RUNNER_FAILED",
        )
        write_result(payload)
        return 1


if __name__ == "__main__":
    sys.exit(main())
