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
import shutil
import subprocess
import sys
import tempfile
from ipaddress import ip_address
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import urlparse


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
    "site_bootstrap.install_apps",
    "site_app.install",
    "bench.update",
    "oauth.status",
    "oauth.configure",
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
SAFE_STATUS_KEYS = {
    "access_token_url",
    "secret_configured",
}
SITE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,190}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,190}$")
APP_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,79}$")
RELEASE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,139}$")
PROVIDER_RE = re.compile(r"^[a-z0-9][a-z0-9_ -]{0,80}$")
URL_RE = re.compile(r"^https://[A-Za-z0-9][A-Za-z0-9_.:/?&=%#@+~,-]*$")
RELATIVE_ENDPOINT_RE = re.compile(r"^/[A-Za-z0-9_./?&=%#@+~,-]*$")


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
BENCH_EXECUTABLE = os.environ.get("BENCH_EXECUTABLE", "").strip()
FAKE_FRAPPE_SETUP = os.environ.get("LENS_COMMAND_FAKE_FRAPPE_SETUP") == "1"
MAX_SETUP_ARGS_BYTES = int(os.environ.get("LENS_COMMAND_MAX_SETUP_ARGS_BYTES", "16384"))
OAUTH_CLIENT_SECRET_PATH = Path(
    os.environ.get("LENS_COMMAND_OAUTH_CLIENT_SECRET_PATH", "/lenscloud/secrets/client_secret")
)


def sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            if str(key) not in SAFE_STATUS_KEYS and SENSITIVE_KEY_RE.search(str(key)):
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


def scrub_provider(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def require_string(args: dict[str, Any], key: str, *, max_length: int = 500) -> str:
    value = args.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure requires {key}")
    value = value.strip()
    if len(value) > max_length:
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} is too long")
    return value


def optional_string(args: dict[str, Any], key: str, *, max_length: int = 500) -> str:
    value = args.get(key, "")
    if value is None:
        return ""
    if not isinstance(value, str):
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} must be a string")
    value = value.strip()
    if len(value) > max_length:
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} is too long")
    return value


def require_endpoint(value: str, key: str) -> str:
    if not (URL_RE.match(value) or RELATIVE_ENDPOINT_RE.match(value)):
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} must be https URL or relative endpoint")
    return value


def require_https_url(value: str, key: str) -> str:
    if not URL_RE.match(value):
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} must be an https URL")
    return value


def optional_bool(args: dict[str, Any], key: str, *, default: bool = False) -> bool:
    value = args.get(key, default)
    if not isinstance(value, bool):
        raise CommandError("INVALID_ARGUMENTS", f"oauth.configure {key} must be a boolean")
    return value


def is_local_dev_http_url(value: str) -> bool:
    parsed = urlparse(value)
    if parsed.scheme != "http" or not parsed.netloc or not parsed.hostname:
        return False
    if parsed.username or parsed.password:
        return False
    hostname = parsed.hostname.lower().rstrip(".")
    if hostname == "localhost" or hostname.endswith(".localhost"):
        return True
    try:
        return ip_address(hostname).is_loopback
    except ValueError:
        return False


def require_oauth_base_url(value: str, *, allow_local_oauth_http: bool) -> str:
    if URL_RE.match(value):
        return value
    if allow_local_oauth_http and is_local_dev_http_url(value):
        return value
    if value.startswith("http://"):
        if allow_local_oauth_http:
            raise CommandError(
                "INVALID_ARGUMENTS",
                "oauth.configure base_url plain HTTP is allowed only for localhost/local-dev URLs",
            )
        raise CommandError(
            "INVALID_ARGUMENTS",
            "oauth.configure base_url must be an https URL unless allow_local_oauth_http is true",
        )
    raise CommandError("INVALID_ARGUMENTS", "oauth.configure base_url must be an https URL")


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
    target_payload = {
        "namespace": target.get("namespace"),
        "bench": target.get("bench"),
    }
    if target.get("site") not in (None, ""):
        target_payload["site"] = target.get("site")
    payload = {
        "phase": phase,
        "commandId": current_request.get("commandId"),
        "command": command,
        "target": target_payload,
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
    if command == "bench.update":
        if site:
            raise CommandError("INVALID_ARGUMENTS", "bench.update target must not include site")
    elif not SITE_RE.match(site) or ".." in site or "/" in site:
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
    bench_site_alias = (BENCH_PATH / site).resolve()
    created_alias = False
    with tempfile.TemporaryDirectory(prefix="lenscloud-sites-") as temp_name:
        temp_sites = Path(temp_name)
        try:
            if not bench_site_alias.exists():
                (bench_site_alias / "logs").mkdir(parents=True, exist_ok=True)
                created_alias = True
            elif bench_site_alias.is_dir():
                (bench_site_alias / "logs").mkdir(parents=True, exist_ok=True)
            else:
                raise CommandError("TARGET_MISMATCH", "bench-local site log path is not a directory")

            for metadata_name in ("common_site_config.json", "apps.txt", "apps.json"):
                for metadata_path in (SITES_PATH / metadata_name, BENCH_PATH / "sites" / metadata_name):
                    if metadata_path.exists():
                        os.symlink(metadata_path.resolve(), temp_sites / metadata_name)
                        break
            if not (temp_sites / "apps.txt").exists():
                apps_root = BENCH_PATH / "apps"
                app_names = sorted(
                    item.name
                    for item in apps_root.iterdir()
                    if item.is_dir() and not item.name.startswith(".")
                ) if apps_root.is_dir() else []
                if app_names:
                    (temp_sites / "apps.txt").write_text("\n".join(app_names) + "\n", encoding="utf-8")
            os.symlink(site_root.resolve(), temp_sites / site)
            yield temp_sites
        finally:
            if created_alias and bench_site_alias.exists():
                shutil.rmtree(bench_site_alias, ignore_errors=True)


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


def fake_oauth_state(site: str) -> tuple[Path, dict[str, Any]]:
    site_root, layout = site_root_path(site)
    state_path = site_root / ".lenscloud_oauth_state.json"
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}
    else:
        state = {}
    if not isinstance(state, dict):
        state = {}
    state.setdefault("_layout", layout)
    return state_path, state


def fake_apps_state(site: str) -> tuple[Path, dict[str, Any]]:
    site_root, layout = site_root_path(site)
    state_path = site_root / ".lenscloud_apps_state.json"
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}
    else:
        state = {}
    if not isinstance(state, dict):
        state = {}
    installed = state.get("installed_apps")
    if not isinstance(installed, list):
        installed = []
    state["installed_apps"] = [str(item).strip().lower() for item in installed if str(item).strip()]
    state["_layout"] = layout
    return state_path, state


def fake_bench_update_state() -> tuple[Path, dict[str, Any]]:
    state_path = SITES_PATH / ".lenscloud_bench_update_state.json"
    if state_path.exists():
        try:
            state = json.loads(state_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            state = {}
    else:
        state = {}
    if not isinstance(state, dict):
        state = {}
    return state_path, state


@contextmanager
def prepared_bench_apps_txt() -> Iterator[None]:
    apps_txt = SITES_PATH / "apps.txt"
    if apps_txt.exists():
        yield
        return

    apps_root = BENCH_PATH / "apps"
    app_names = sorted(
        item.name
        for item in apps_root.iterdir()
        if item.is_dir() and not item.name.startswith(".")
    ) if apps_root.is_dir() else []
    if not app_names:
        raise CommandError("RUNNER_FAILED", "sites/apps.txt was not found and no bench apps were discoverable")
    if "frappe" in app_names:
        app_names = ["frappe"] + [app for app in app_names if app != "frappe"]

    apps_txt.parent.mkdir(parents=True, exist_ok=True)
    apps_txt.write_text("\n".join(app_names) + "\n", encoding="utf-8")
    try:
        yield
    finally:
        try:
            apps_txt.unlink()
        except FileNotFoundError:
            pass


def validate_app_name(value: Any) -> str:
    app = str(value or "").strip().lower()
    if not app or not APP_RE.match(app):
        raise CommandError("INVALID_ARGUMENTS", "app must be a safe lower-case app identifier")
    if app == "frappe":
        raise CommandError("INVALID_ARGUMENTS", "frappe is the base runtime and must not be an install app")
    return app


def validate_install_sequence(value: Any) -> int | None:
    if value in (None, ""):
        return None
    try:
        sequence = int(value)
    except (TypeError, ValueError) as exc:
        raise CommandError("INVALID_ARGUMENTS", "install_sequence must be an integer") from exc
    if sequence < 0 or sequence > 100000:
        raise CommandError("INVALID_ARGUMENTS", "install_sequence must be between 0 and 100000")
    return sequence


def validate_app_batch(command: str, args: dict[str, Any]) -> list[dict[str, Any]]:
    key = "install_apps" if command == "site_bootstrap.install_apps" else "apps"
    apps = args.get(key)
    if apps is None and command == "site_app.install":
        apps = args.get("install_apps")
    if not isinstance(apps, list) or not apps:
        raise CommandError("INVALID_ARGUMENTS", f"{command} requires a non-empty ordered app list")
    if len(apps) > 10:
        raise CommandError("INVALID_ARGUMENTS", f"{command} accepts at most 10 apps")
    clean: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in apps:
        if isinstance(item, str):
            item = {"app": item}
        if not isinstance(item, dict):
            raise CommandError("INVALID_ARGUMENTS", "app install items must be objects")
        unknown = set(item) - {"app", "install_sequence"}
        if unknown:
            raise CommandError("INVALID_ARGUMENTS", "app install item contains unsupported fields")
        app = validate_app_name(item.get("app"))
        if app in seen:
            raise CommandError("INVALID_ARGUMENTS", "app install payload contains duplicate apps")
        seen.add(app)
        clean.append({"app": app, "install_sequence": validate_install_sequence(item.get("install_sequence"))})
    return clean


def validate_target_release(args: dict[str, Any]) -> str:
    unknown = set(args) - {"target_release"}
    if unknown:
        raise CommandError("INVALID_ARGUMENTS", "bench.update contains unsupported args")
    target_release = str(args.get("target_release") or "").strip()
    if not target_release or not RELEASE_RE.match(target_release):
        raise CommandError("INVALID_ARGUMENTS", "bench.update requires a safe target_release")
    return target_release


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


def validate_oauth_provider(args: dict[str, Any]) -> str:
    provider = str(args.get("provider") or "").strip().lower()
    if not provider:
        provider_name = str(args.get("provider_name") or "").strip()
        provider = scrub_provider(provider_name)
    if not provider or not PROVIDER_RE.match(provider) or provider != scrub_provider(provider):
        raise CommandError("INVALID_ARGUMENTS", "oauth provider must be a safe lower-case provider key")
    return provider


def validate_oauth_config_args(args: dict[str, Any]) -> dict[str, Any]:
    allowed_keys = {
        "provider",
        "provider_name",
        "social_login_provider",
        "enable_social_login",
        "client_id",
        "client_secret_source",
        "base_url",
        "authorize_url",
        "access_token_url",
        "redirect_url",
        "api_endpoint",
        "custom_base_url",
        "auth_url_data",
        "sign_ups",
        "api_endpoint_args",
        "user_id_property",
        "icon",
        "allow_local_oauth_http",
    }
    unknown_keys = set(args) - allowed_keys
    if unknown_keys:
        raise CommandError("INVALID_ARGUMENTS", "oauth.configure contains unsupported args")
    if "client_secret" in args:
        raise CommandError("INVALID_ARGUMENTS", "oauth.configure args must not contain secret values")

    provider = validate_oauth_provider(args)
    provider_name = require_string(args, "provider_name", max_length=140)
    if scrub_provider(provider_name) != provider:
        raise CommandError("INVALID_ARGUMENTS", "provider must match scrubbed provider_name")

    auth_url_data = args.get("auth_url_data", {"response_type": "code", "scope": "openid"})
    if isinstance(auth_url_data, dict):
        auth_url_data = json.dumps(auth_url_data, sort_keys=True, separators=(",", ":"))
    if not isinstance(auth_url_data, str):
        raise CommandError("INVALID_ARGUMENTS", "auth_url_data must be an object or JSON string")
    try:
        parsed_auth_url_data = json.loads(auth_url_data)
    except json.JSONDecodeError as exc:
        raise CommandError("INVALID_ARGUMENTS", "auth_url_data must be valid JSON") from exc
    if not isinstance(parsed_auth_url_data, dict):
        raise CommandError("INVALID_ARGUMENTS", "auth_url_data must be a JSON object")
    if contains_sensitive_key(parsed_auth_url_data):
        raise CommandError("INVALID_ARGUMENTS", "auth_url_data must not contain secret values")

    client_secret_source = args.get("client_secret_source", "mounted_file")
    if client_secret_source != "mounted_file":
        raise CommandError("INVALID_ARGUMENTS", "oauth.configure requires client_secret_source=mounted_file")

    sign_ups = optional_string(args, "sign_ups", max_length=10)
    if sign_ups not in {"", "Allow", "Deny"}:
        raise CommandError("INVALID_ARGUMENTS", "sign_ups must be empty, Allow, or Deny")
    allow_local_oauth_http = optional_bool(args, "allow_local_oauth_http", default=False)

    config = {
        "provider": provider,
        "provider_name": provider_name,
        "social_login_provider": optional_string(args, "social_login_provider", max_length=40) or "Custom",
        "enable_social_login": 1 if bool(args.get("enable_social_login", True)) else 0,
        "client_id": require_string(args, "client_id", max_length=255),
        "base_url": require_oauth_base_url(
            require_string(args, "base_url", max_length=500),
            allow_local_oauth_http=allow_local_oauth_http,
        ),
        "authorize_url": require_endpoint(require_string(args, "authorize_url", max_length=500), "authorize_url"),
        "access_token_url": require_endpoint(require_string(args, "access_token_url", max_length=500), "access_token_url"),
        "redirect_url": require_https_url(require_string(args, "redirect_url", max_length=500), "redirect_url"),
        "api_endpoint": require_endpoint(require_string(args, "api_endpoint", max_length=500), "api_endpoint"),
        "custom_base_url": 1 if bool(args.get("custom_base_url", True)) else 0,
        "auth_url_data": auth_url_data,
        "sign_ups": sign_ups,
    }
    optional_fields = {
        "api_endpoint_args": optional_string(args, "api_endpoint_args", max_length=2000),
        "user_id_property": optional_string(args, "user_id_property", max_length=140),
        "icon": optional_string(args, "icon", max_length=500),
    }
    config.update({key: value for key, value in optional_fields.items() if value})
    return config


def read_oauth_client_secret() -> str:
    if not OAUTH_CLIENT_SECRET_PATH.is_file():
        raise CommandError("INVALID_ARGUMENTS", "oauth.configure requires mounted client_secret file")
    secret = OAUTH_CLIENT_SECRET_PATH.read_text(encoding="utf-8").strip()
    if not secret:
        raise CommandError("INVALID_ARGUMENTS", "mounted client_secret file is empty")
    if len(secret.encode("utf-8")) > 4096:
        raise CommandError("INVALID_ARGUMENTS", "mounted client_secret file is too large")
    return secret


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
    def get_pending_setup_apps():
        installed_apps = frappe.client_cache.get_doc("Installed Applications")
        return [
            item.app_name
            for item in installed_apps.installed_applications
            if item.has_setup_wizard and not item.is_setup_complete
        ]

    def status_payload():
        setup_complete = bool(frappe.is_setup_complete())
        pending_apps = [] if setup_complete else get_pending_setup_apps()
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


FRAPPE_OAUTH_SCRIPT = r"""
import json
import sys

site = sys.argv[1]
sites_path = sys.argv[2]
operation = sys.argv[3]
payload = json.loads(sys.stdin.read() or "{}")

import frappe

frappe.init(site=site, sites_path=sites_path)
frappe.connect()

try:
    provider = payload["provider"]

    def status_payload():
        exists = bool(frappe.db.exists("Social Login Key", provider))
        if not exists:
            return {
                "configured": False,
                "enabled": False,
                "provider": provider,
                "secret_configured": False,
            }
        doc = frappe.get_doc("Social Login Key", provider)
        secret_configured = bool(doc.get_password("client_secret", raise_exception=False))
        return {
            "configured": True,
            "enabled": bool(doc.enable_social_login),
            "provider": doc.name,
            "provider_name": doc.provider_name,
            "social_login_provider": doc.social_login_provider,
            "client_id": doc.client_id,
            "base_url": doc.base_url,
            "authorize_url": doc.authorize_url,
            "access_token_url": doc.access_token_url,
            "redirect_url": doc.redirect_url,
            "api_endpoint": doc.api_endpoint,
            "custom_base_url": bool(doc.custom_base_url),
            "sign_ups": doc.sign_ups or "",
            "secret_configured": secret_configured,
        }

    if operation == "status":
        print(json.dumps(status_payload(), sort_keys=True, separators=(",", ":")))
    elif operation == "configure":
        config = payload["config"]
        secret = payload["client_secret"]
        before = status_payload()
        if frappe.db.exists("Social Login Key", provider):
            doc = frappe.get_doc("Social Login Key", provider)
        else:
            doc = frappe.new_doc("Social Login Key")
            doc.name = provider
        for key, value in config.items():
            if key != "provider":
                doc.set(key, value)
        doc.client_secret = secret
        if doc.is_new():
            doc.insert(ignore_permissions=True)
        else:
            doc.save(ignore_permissions=True)
        frappe.db.commit()
        after = status_payload()
        after["changed"] = before != after
        print(json.dumps(after, sort_keys=True, separators=(",", ":")))
    else:
        raise RuntimeError("unsupported oauth operation")
finally:
    if getattr(frappe.local, "db", None):
        frappe.db.close()
    frappe.destroy()
"""


FRAPPE_APP_INSTALL_SCRIPT = r"""
import json
import sys

site = sys.argv[1]
sites_path = sys.argv[2]
payload = json.loads(sys.stdin.read() or "{}")

import frappe
from frappe.installer import install_app

frappe.init(site=site, sites_path=sites_path)
frappe.connect()

attempted = [item["app"] for item in payload.get("apps", [])]
installed_apps = []
skipped_apps = []
failed_app = None
error_excerpt = None

try:
    current_apps = set(frappe.get_installed_apps())
    for item in payload.get("apps", []):
        app = item["app"]
        if app in current_apps:
            skipped_apps.append(app)
            continue
        try:
            try:
                install_app(app, verbose=False, set_as_patched=True)
            except TypeError:
                install_app(app, verbose=False)
            frappe.db.commit()
            installed_apps.append(app)
            current_apps.add(app)
        except Exception as exc:
            frappe.db.rollback()
            failed_app = app
            error_excerpt = str(exc)[:500]
            break
    print(json.dumps({
        "attempted_apps": attempted,
        "installed_apps": installed_apps,
        "skipped_apps": skipped_apps,
        "failed_app": failed_app,
        "error_excerpt": error_excerpt,
        "exit_code": 1 if failed_app else 0,
    }, sort_keys=True, separators=(",", ":")))
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
        env = dict(os.environ)
        env["FRAPPE_STREAM_LOGGING"] = "1"
        try:
            completed = subprocess.run(
                [str(BENCH_PYTHON), "-c", FRAPPE_SETUP_SCRIPT, site, str(temp_sites), operation, str(timeout)],
                input=json.dumps(args, sort_keys=True, separators=(",", ":")),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(BENCH_PATH),
                env=env,
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


def run_frappe_app_install(site: str, apps: list[dict[str, Any]], timeout: int) -> dict[str, Any]:
    if FAKE_FRAPPE_SETUP:
        state_path, state = fake_apps_state(site)
        installed_set = set(state["installed_apps"])
        attempted = [item["app"] for item in apps]
        installed_apps = []
        skipped_apps = []
        for app in attempted:
            if app in installed_set:
                skipped_apps.append(app)
                continue
            installed_set.add(app)
            installed_apps.append(app)
        state["installed_apps"] = sorted(installed_set)
        state_path.write_text(json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        return {
            "attempted_apps": attempted,
            "installed_apps": installed_apps,
            "skipped_apps": skipped_apps,
            "failed_app": None,
            "error_excerpt": None,
            "exit_code": 0,
            "layout": state.get("_layout"),
        }

    if not BENCH_PYTHON.is_file():
        raise CommandError("RUNNER_FAILED", "bench Python environment was not found")

    Path("/home/frappe/logs").mkdir(parents=True, exist_ok=True)
    with prepared_frappe_sites_path(site) as temp_sites:
        env = dict(os.environ)
        env["FRAPPE_STREAM_LOGGING"] = "1"
        try:
            completed = subprocess.run(
                [str(BENCH_PYTHON), "-c", FRAPPE_APP_INSTALL_SCRIPT, site, str(temp_sites)],
                input=json.dumps({"apps": apps}, sort_keys=True, separators=(",", ":")),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(BENCH_PATH),
                env=env,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CommandError("TIMEOUT", "app install command timed out", "Timed Out") from exc

    if completed.returncode != 0:
        raise CommandError("RUNNER_FAILED", "app install command failed with sanitized error")
    output_lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if not output_lines:
        raise CommandError("RUNNER_FAILED", "app install command did not return a result")
    try:
        payload = json.loads(output_lines[-1])
    except json.JSONDecodeError as exc:
        raise CommandError("RUNNER_FAILED", "app install command returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise CommandError("RUNNER_FAILED", "app install command returned invalid result")
    if payload.get("exit_code"):
        payload["error_excerpt"] = sanitize(str(payload.get("error_excerpt") or ""))[:500]
    return payload


def command_site_app_install(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    apps = validate_app_batch(command, args)
    timeout = request_timeout_seconds()
    state = run_frappe_app_install(site, apps, timeout)
    failed_app = state.get("failed_app")
    installed_apps = state.get("installed_apps") if isinstance(state.get("installed_apps"), list) else []
    skipped_apps = state.get("skipped_apps") if isinstance(state.get("skipped_apps"), list) else []
    attempted_apps = state.get("attempted_apps") if isinstance(state.get("attempted_apps"), list) else [item["app"] for item in apps]
    if failed_app:
        summary = f"App install failed for {failed_app}"
    elif installed_apps:
        summary = "Installed requested apps"
    else:
        summary = "All requested apps already installed"
    return result(
        phase="Failed" if failed_app else "Succeeded",
        command=command,
        target=target,
        summary=summary,
        changed=bool(installed_apps),
        code="RUNNER_FAILED" if failed_app else None,
        details={
            "attempted_apps": attempted_apps,
            "installed_apps": installed_apps,
            "skipped_apps": skipped_apps,
            "failed_app": failed_app,
            "exit_code": int(state.get("exit_code") or 0),
            "error_excerpt": state.get("error_excerpt"),
            "layout": state.get("layout"),
        },
        display={
            "label": "App install",
            "value": summary,
            "kind": "app-install",
            "rawValue": {
                "attempted_apps": attempted_apps,
                "installed_apps": installed_apps,
                "skipped_apps": skipped_apps,
                "failed_app": failed_app,
            },
            "safe": True,
        },
    )


def bench_executable() -> list[str]:
    if BENCH_EXECUTABLE:
        configured = Path(BENCH_EXECUTABLE)
        if configured.is_file():
            return [str(configured)]
        raise CommandError("RUNNER_FAILED", "configured bench executable was not found")
    discovered = shutil.which("bench")
    if discovered:
        return [discovered]
    bench_env_executable = BENCH_PATH / "env" / "bin" / "bench"
    if bench_env_executable.is_file():
        return [str(bench_env_executable)]
    if BENCH_PYTHON.is_file():
        return [str(BENCH_PYTHON), "-m", "bench.cli"]
    raise CommandError("RUNNER_FAILED", "bench executable was not found")


def run_bench_update(target_release: str, timeout: int) -> dict[str, Any]:
    if FAKE_FRAPPE_SETUP:
        state_path, state = fake_bench_update_state()
        previous = state.get("target_release")
        changed = previous != target_release
        state.update(
            {
                "target_release": target_release,
                "last_command": "bench --site all set-config/migrate sequence",
                "exit_code": 0,
            }
        )
        state_path.write_text(json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        return {
            "target_release": target_release,
            "changed": changed,
            "exit_code": 0,
            "operation": "bench --site all maintenance/pause/migrate",
        }

    executable = bench_executable()
    steps = [
        ("maintenance_on", ["--site", "all", "set-config", "-p", "maintenance_mode", "1"]),
        ("scheduler_pause", ["--site", "all", "set-config", "-p", "pause_scheduler", "1"]),
        ("migrate", ["--site", "all", "migrate"]),
    ]
    cleanup_steps = [
        ("maintenance_off", ["--site", "all", "set-config", "-p", "maintenance_mode", "0"]),
        ("scheduler_resume", ["--site", "all", "set-config", "-p", "pause_scheduler", "0"]),
    ]
    failed_step = None
    failed_result: subprocess.CompletedProcess[str] | None = None
    completed_steps: list[str] = []
    try:
        with prepared_bench_apps_txt():
            for step, args in steps:
                completed = subprocess.run(
                    executable + args,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    cwd=str(BENCH_PATH),
                    env=dict(os.environ),
                    timeout=timeout,
                    check=False,
                )
                if completed.returncode != 0:
                    failed_step = step
                    failed_result = completed
                    break
                completed_steps.append(step)
            for step, args in cleanup_steps:
                cleanup = subprocess.run(
                    executable + args,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    cwd=str(BENCH_PATH),
                    env=dict(os.environ),
                    timeout=timeout,
                    check=False,
                )
                if cleanup.returncode != 0 and failed_result is None:
                    failed_step = step
                    failed_result = cleanup
                    break
                if cleanup.returncode == 0:
                    completed_steps.append(step)
    except subprocess.TimeoutExpired as exc:
        raise CommandError("TIMEOUT", "bench update command timed out", "Timed Out") from exc

    exit_code = failed_result.returncode if failed_result else 0
    return {
        "target_release": target_release,
        "changed": exit_code == 0,
        "exit_code": exit_code,
        "operation": "bench --site all maintenance/pause/migrate",
        "completed_steps": completed_steps,
        "failed_step": failed_step,
        "error_excerpt": sanitize((failed_result.stderr or failed_result.stdout or "")[-500:]) if failed_result else None,
    }


def command_bench_update(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    target_release = validate_target_release(args)
    timeout = request_timeout_seconds()
    state = run_bench_update(target_release, timeout)
    exit_code = int(state.get("exit_code") or 0)
    return result(
        phase="Succeeded" if exit_code == 0 else "Failed",
        command=command,
        target=target,
        summary="Bench update completed" if exit_code == 0 else "Bench update failed",
        changed=bool(state.get("changed")),
        code=None if exit_code == 0 else "RUNNER_FAILED",
        details={
            "target_release": target_release,
            "operation": state.get("operation"),
            "exit_code": exit_code,
            "completed_steps": state.get("completed_steps"),
            "failed_step": state.get("failed_step"),
            "error_excerpt": state.get("error_excerpt"),
        },
        display={
            "label": "Bench update",
            "value": "Completed" if exit_code == 0 else "Failed",
            "kind": "bench-update",
            "rawValue": {
                "target_release": target_release,
                "exit_code": exit_code,
            },
            "safe": True,
        },
    )


def oauth_display(state: dict[str, Any]) -> dict[str, Any]:
    configured = bool(state.get("configured"))
    enabled = bool(state.get("enabled"))
    if not configured:
        value = "Missing"
    elif enabled:
        value = "Enabled"
    else:
        value = "Disabled"
    return {
        "label": "Social login",
        "value": value,
        "kind": "oauth-status",
        "rawValue": {
            "configured": configured,
            "enabled": enabled,
            "provider": state.get("provider"),
            "provider_name": state.get("provider_name"),
            "secret_configured": bool(state.get("secret_configured")),
        },
        "safe": True,
    }


def run_frappe_oauth(site: str, operation: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    if FAKE_FRAPPE_SETUP:
        state_path, state = fake_oauth_state(site)
        provider = str(payload["provider"])
        existing = state.get(provider) if isinstance(state.get(provider), dict) else None
        if operation == "status":
            if not existing:
                return {
                    "configured": False,
                    "enabled": False,
                    "provider": provider,
                    "secret_configured": False,
                    "layout": state.get("_layout"),
                }
            safe_existing = dict(existing)
            safe_existing["layout"] = state.get("_layout")
            return safe_existing
        if operation == "configure":
            config = dict(payload["config"])
            before = dict(existing) if existing else None
            configured = {
                "configured": True,
                "enabled": bool(config.get("enable_social_login")),
                "provider": provider,
                "provider_name": config.get("provider_name"),
                "social_login_provider": config.get("social_login_provider"),
                "client_id": config.get("client_id"),
                "base_url": config.get("base_url"),
                "authorize_url": config.get("authorize_url"),
                "access_token_url": config.get("access_token_url"),
                "redirect_url": config.get("redirect_url"),
                "api_endpoint": config.get("api_endpoint"),
                "custom_base_url": bool(config.get("custom_base_url")),
                "sign_ups": config.get("sign_ups") or "",
                "secret_configured": bool(payload.get("client_secret")),
            }
            state[provider] = configured
            state_path.write_text(json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
            configured["changed"] = before != configured
            configured["layout"] = state.get("_layout")
            return configured
        raise CommandError("COMMAND_UNSUPPORTED", "unsupported oauth operation", "Unsupported")

    if not BENCH_PYTHON.is_file():
        raise CommandError("RUNNER_FAILED", "bench Python environment was not found")

    Path("/home/frappe/logs").mkdir(parents=True, exist_ok=True)

    with prepared_frappe_sites_path(site) as temp_sites:
        env = dict(os.environ)
        env["FRAPPE_STREAM_LOGGING"] = "1"
        try:
            completed = subprocess.run(
                [str(BENCH_PYTHON), "-c", FRAPPE_OAUTH_SCRIPT, site, str(temp_sites), operation],
                input=json.dumps(payload, sort_keys=True, separators=(",", ":")),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(BENCH_PATH),
                env=env,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise CommandError("TIMEOUT", "oauth command timed out", "Timed Out") from exc

    if completed.returncode != 0:
        raise CommandError("RUNNER_FAILED", "oauth command failed with sanitized error")

    output_lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if not output_lines:
        raise CommandError("RUNNER_FAILED", "oauth command did not return a result")
    try:
        result_payload = json.loads(output_lines[-1])
    except json.JSONDecodeError as exc:
        raise CommandError("RUNNER_FAILED", "oauth command returned invalid JSON") from exc
    if not isinstance(result_payload, dict):
        raise CommandError("RUNNER_FAILED", "oauth command returned invalid result")
    return result_payload


def command_oauth(command: str, target: dict[str, Any], args: dict[str, Any]) -> dict[str, Any]:
    site = str(target["site"])
    timeout = request_timeout_seconds()

    if command == "oauth.status":
        provider = validate_oauth_provider(args)
        unsupported_args = set(args) - {"provider", "provider_name"}
        if unsupported_args:
            raise CommandError("INVALID_ARGUMENTS", "oauth.status accepts only provider or provider_name")
        state = run_frappe_oauth(site, "status", {"provider": provider}, timeout)
        configured = bool(state.get("configured"))
        enabled = bool(state.get("enabled"))
        return result(
            phase="Succeeded",
            command=command,
            target=target,
            summary=(
                "Social login is enabled"
                if configured and enabled
                else "Social login is configured but disabled"
                if configured
                else "Social login is not configured"
            ),
            changed=False,
            details={
                "provider": provider,
                "configured": configured,
                "enabled": enabled,
                "provider_name": state.get("provider_name"),
                "social_login_provider": state.get("social_login_provider"),
                "client_id": state.get("client_id"),
                "base_url": state.get("base_url"),
                "authorize_url": state.get("authorize_url"),
                "access_token_url": state.get("access_token_url"),
                "redirect_url": state.get("redirect_url"),
                "api_endpoint": state.get("api_endpoint"),
                "custom_base_url": bool(state.get("custom_base_url")),
                "sign_ups": state.get("sign_ups") or "",
                "secret_configured": bool(state.get("secret_configured")),
            },
            display=oauth_display(state),
        )

    if command == "oauth.configure":
        config = validate_oauth_config_args(args)
        client_secret = read_oauth_client_secret()
        state = run_frappe_oauth(
            site,
            "configure",
            {
                "provider": config["provider"],
                "config": config,
                "client_secret": client_secret,
            },
            timeout,
        )
        configured = bool(state.get("configured"))
        enabled = bool(state.get("enabled"))
        changed = bool(state.get("changed"))
        return result(
            phase="Succeeded" if configured else "Failed",
            command=command,
            target=target,
            summary="Social login configured" if configured else "Social login was not configured",
            changed=changed,
            code=None if configured else "RUNNER_FAILED",
            details={
                "provider": config["provider"],
                "configured": configured,
                "enabled": enabled,
                "provider_name": state.get("provider_name"),
                "social_login_provider": state.get("social_login_provider"),
                "client_id": state.get("client_id"),
                "base_url": state.get("base_url"),
                "authorize_url": state.get("authorize_url"),
                "access_token_url": state.get("access_token_url"),
                "redirect_url": state.get("redirect_url"),
                "api_endpoint": state.get("api_endpoint"),
                "custom_base_url": bool(state.get("custom_base_url")),
                "sign_ups": state.get("sign_ups") or "",
                "secret_configured": bool(state.get("secret_configured")),
            },
            display=oauth_display(state),
        )

    raise CommandError("COMMAND_UNSUPPORTED", "unsupported oauth command", "Unsupported")


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
    if command.startswith("site_bootstrap.") or command.startswith("site_app."):
        return command_site_app_install(command, target, args)
    if command.startswith("bench."):
        return command_bench_update(command, target, args)
    if command.startswith("oauth."):
        return command_oauth(command, target, args)
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
