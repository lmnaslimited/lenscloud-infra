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
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator


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
    "site_setup.status",
    "site_setup.complete",
    "bench_test.trigger",
    "bench_test.status",
    "latp.trigger",
    "latp.status",
}

RUNNER_PENDING = {
    "backup.create",
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
BENCH_PYTHON = Path(os.environ.get("BENCH_PYTHON", str(BENCH_PATH / "env" / "bin" / "python")))
FAKE_FRAPPE_SETUP = os.environ.get("LENS_COMMAND_FAKE_FRAPPE_SETUP") == "1"
MAX_SETUP_ARGS_BYTES = int(os.environ.get("LENS_COMMAND_MAX_SETUP_ARGS_BYTES", "16384"))


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


def contains_sensitive_key(value: Any) -> bool:
    if isinstance(value, dict):
        for key, item in value.items():
            if SENSITIVE_KEY_RE.search(str(key)) or contains_sensitive_key(item):
                return True
    elif isinstance(value, list):
        return any(contains_sensitive_key(item) for item in value)
    return False


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


def request_timeout_seconds(default: int = 300, maximum: int = 900) -> int:
    raw_timeout = current_request.get("timeoutSeconds", default)
    try:
        timeout = int(raw_timeout)
    except (TypeError, ValueError) as exc:
        raise CommandError("INVALID_ARGUMENTS", "timeoutSeconds must be an integer") from exc
    if timeout <= 0 or timeout > maximum:
        raise CommandError("INVALID_ARGUMENTS", f"timeoutSeconds must be between 1 and {maximum}")
    return timeout


def candidate_site_roots(site: str) -> list[tuple[str, Path]]:
    return [
        ("sites-root", SITES_PATH / site),
        ("frappe-sites", SITES_PATH / "frappe-sites" / site),
    ]


def site_root_path(site: str) -> tuple[Path, str]:
    expected_root = SITES_PATH.resolve()
    matches: list[tuple[str, Path]] = []
    for layout, site_root in candidate_site_roots(site):
        path = site_root.resolve()
        if expected_root not in path.parents and path != expected_root:
            raise CommandError("TARGET_MISMATCH", "site path escapes bench sites directory")
        if (path / "site_config.json").is_file():
            matches.append((layout, path))
    if len(matches) > 1:
        raise CommandError("TARGET_MISMATCH", "site_config.json matched multiple supported layouts")
    if not matches:
        raise CommandError("TARGET_NOT_FOUND", "site_config.json was not found")
    layout, path = matches[0]
    if expected_root not in path.parents and path != expected_root:
        raise CommandError("TARGET_MISMATCH", "site path escapes bench sites directory")
    return path, layout


def site_config_path(site: str) -> tuple[Path, str]:
    site_root, layout = site_root_path(site)
    path = (site_root / "site_config.json").resolve()
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


@contextmanager
def prepared_frappe_sites_path(site: str) -> Iterator[Path]:
    site_root, _layout = site_root_path(site)
    with tempfile.TemporaryDirectory(prefix="lenscloud-sites-") as temp_name:
        temp_sites = Path(temp_name)
        for metadata_name in ("common_site_config.json", "apps.txt", "apps.json"):
            metadata_path = SITES_PATH / metadata_name
            if metadata_path.exists():
                os.symlink(metadata_path.resolve(), temp_sites / metadata_name)
        os.symlink(site_root.resolve(), temp_sites / site)
        yield temp_sites


def fake_setup_state(site: str) -> tuple[Path, dict[str, Any]]:
    site_root, layout = site_root_path(site)
    state_path = site_root / ".lenscloud_setup_state.json"
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}
    else:
        state = {}
    return state_path, {"layout": layout, "setup_complete": bool(state.get("setup_complete"))}


def validate_setup_args(args: dict[str, Any]) -> dict[str, Any]:
    setup_args = args.get("setup_args", args)
    if not isinstance(setup_args, dict):
        raise CommandError("INVALID_ARGUMENTS", "site_setup.complete args must be an object")
    encoded = json.dumps(setup_args, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_SETUP_ARGS_BYTES:
        raise CommandError("INVALID_ARGUMENTS", "site_setup.complete args are too large")
    if contains_sensitive_key(setup_args):
        raise CommandError("INVALID_ARGUMENTS", "site_setup.complete args contain a sensitive key")
    return setup_args


FRAPPE_SETUP_SCRIPT = r"""
import json
import sys
import time

site = sys.argv[1]
sites_path = sys.argv[2]
operation = sys.argv[3]
timeout_seconds = int(sys.argv[4])
payload = json.loads(sys.stdin.read() or "{}")

import frappe

frappe.init(site=site, sites_path=sites_path)
frappe.connect()

try:
    from frappe.core.doctype.installed_applications.installed_applications import (
        get_setup_wizard_pending_apps,
    )

    def status_payload():
        setup_complete = bool(frappe.is_setup_complete())
        pending_apps = [] if setup_complete else list(get_setup_wizard_pending_apps())
        return {
            "setup_complete": setup_complete,
            "setup_required": not setup_complete,
            "pending_apps": pending_apps,
        }

    if operation == "status":
        print(json.dumps(status_payload(), sort_keys=True, separators=(",", ":")))
    elif operation == "complete":
        from frappe.desk.page.setup_wizard.setup_wizard import setup_complete

        response = setup_complete(payload)
        frappe.db.commit()
        response_status = response.get("status") if isinstance(response, dict) else None
        state = status_payload()
        if response_status == "registered" and not state["setup_complete"]:
            deadline = time.monotonic() + timeout_seconds
            while time.monotonic() < deadline:
                time.sleep(5)
                state = status_payload()
                if state["setup_complete"]:
                    break
        state["response_status"] = response_status
        print(json.dumps(state, sort_keys=True, separators=(",", ":")))
    else:
        raise RuntimeError("unsupported setup operation")
finally:
    if getattr(frappe.local, "db", None):
        frappe.db.close()
    frappe.destroy()
"""


def run_frappe_setup(site: str, operation: str, args: dict[str, Any], timeout: int) -> dict[str, Any]:
    if FAKE_FRAPPE_SETUP:
        state_path, state = fake_setup_state(site)
        if operation == "complete":
            state["setup_complete"] = True
            state["setup_required"] = False
            state_path.write_text(json.dumps({"setup_complete": True}) + "\n", encoding="utf-8")
        else:
            state["setup_required"] = not state["setup_complete"]
        state.setdefault("pending_apps", [] if state["setup_complete"] else ["frappe"])
        return state

    if not BENCH_PYTHON.is_file():
        raise CommandError("RUNNER_FAILED", "bench Python environment was not found")

    Path("/home/frappe/logs").mkdir(parents=True, exist_ok=True)

    with prepared_frappe_sites_path(site) as temp_sites:
        try:
            completed = subprocess.run(
                [str(BENCH_PYTHON), "-c", FRAPPE_SETUP_SCRIPT, site, str(temp_sites), operation, str(timeout)],
                input=json.dumps(args, sort_keys=True, separators=(",", ":")),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(BENCH_PATH),
                timeout=timeout + 15,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CommandError("TIMEOUT", "site setup command timed out", "Timed Out") from exc

    if completed.returncode != 0:
        raise CommandError("RUNNER_FAILED", "site setup command failed with sanitized error")

    output_lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if not output_lines:
        raise CommandError("RUNNER_FAILED", "site setup command did not return a result")
    try:
        payload = json.loads(output_lines[-1])
    except json.JSONDecodeError as exc:
        raise CommandError("RUNNER_FAILED", "site setup command returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise CommandError("RUNNER_FAILED", "site setup command returned invalid result")
    return payload


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


def backup_dir_for_site(site: str) -> tuple[Path, str]:
    site_root, layout = site_root_path(site)
    path = (site_root / "private" / "backups").resolve()
    if site_root not in path.parents:
        raise CommandError("TARGET_MISMATCH", "backup path escapes site directory")
    return path, layout


def backup_files(site: str) -> tuple[Path, str, list[dict[str, Any]]]:
    backup_dir, layout = backup_dir_for_site(site)
    if not backup_dir.exists():
        return backup_dir, layout, []
    if not backup_dir.is_dir():
        raise CommandError("RUNNER_FAILED", "backup path is not a directory")
    files = []
    for path in sorted(backup_dir.iterdir(), key=lambda item: item.stat().st_mtime, reverse=True):
        if not path.is_file():
            continue
        stat = path.stat()
        files.append(
            {
                "name": path.name,
                "sizeBytes": stat.st_size,
                "modifiedAt": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
            }
        )
    return backup_dir, layout, files


def command_backup(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    _, layout, before = backup_files(site)

    if command == "backup.status":
        latest = before[0] if before else None
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary="Read backup status",
            details={"layout": layout, "count": len(before), "latest": latest},
            display={
                "label": "Backups",
                "value": f"{len(before)} available",
                "kind": "backup-status",
                "rawValue": {"count": len(before), "latest": latest},
                "safe": True,
            },
        )

    raise CommandError("COMMAND_UNSUPPORTED", "unsupported backup command", "Unsupported")


def command_site_setup(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    timeout = request_timeout_seconds()

    if command == "site_setup.status":
        if args:
            raise CommandError("INVALID_ARGUMENTS", "site_setup.status does not accept args")
        setup_state = run_frappe_setup(site, "status", {}, timeout)
        complete = bool(setup_state.get("setup_complete"))
        pending_apps = setup_state.get("pending_apps") if isinstance(setup_state.get("pending_apps"), list) else []
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary="Setup wizard is complete" if complete else "Setup wizard is pending",
            changed=False,
            details={
                "setup_complete": complete,
                "setup_required": not complete,
                "pending_apps": pending_apps,
            },
            display={
                "label": "Setup wizard",
                "value": "Complete" if complete else "Pending",
                "kind": "setup-status",
                "rawValue": {"setup_complete": complete, "pending_apps": pending_apps},
                "safe": True,
            },
        )

    if command == "site_setup.complete":
        setup_args = validate_setup_args(args)
        before = run_frappe_setup(site, "status", {}, timeout)
        before_complete = bool(before.get("setup_complete"))
        after = run_frappe_setup(site, "complete", setup_args, timeout)
        after_complete = bool(after.get("setup_complete"))
        pending_apps = after.get("pending_apps") if isinstance(after.get("pending_apps"), list) else []
        response_status = after.get("response_status")
        return result(
            phase="Succeeded" if after_complete else "Failed",
            command=command,
            target=target,
            summary="Setup wizard completed" if after_complete else "Setup wizard did not complete",
            changed=not before_complete and after_complete,
            code=None if after_complete else "RUNNER_FAILED",
            details={
                "setup_complete": after_complete,
                "setup_required": not after_complete,
                "pending_apps": pending_apps,
                "response_status": response_status,
                "idempotent": before_complete and after_complete,
            },
            display={
                "label": "Setup wizard",
                "value": "Complete" if after_complete else "Pending",
                "kind": "setup-status",
                "rawValue": {"setup_complete": after_complete, "pending_apps": pending_apps},
                "safe": True,
            },
        )

    raise CommandError("COMMAND_UNSUPPORTED", "unsupported site_setup command", "Unsupported")


def dispatch(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    if command in RUNNER_PENDING:
        raise CommandError("COMMAND_UNSUPPORTED", "command family is contracted but runner-pending", "Unsupported")
    if command.startswith("backup."):
        return command_backup(command, target, args)
    if command.startswith("restore."):
        raise CommandError("COMMAND_UNSUPPORTED", "restore command requires a finalized destructive runbook", "Unsupported")
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
    if command.startswith("site_setup."):
        return command_site_setup(command, target, args)
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
