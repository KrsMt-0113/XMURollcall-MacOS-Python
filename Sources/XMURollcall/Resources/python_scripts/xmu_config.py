"""
XMU Rollcall config management module adapted for PythonKit interop.
Manages account storage in ~/.xmu_rollcall/config.json.
All functions accept/return JSON strings for easy Swift bridging.
"""

import os
import json
import uuid
from pathlib import Path


def _get_config_dir():
    """Get the configuration directory path."""
    if env_path := os.environ.get("XMU_ROLLCALL_CONFIG_DIR"):
        return Path(env_path)
    try:
        home_dir = Path.home() / ".xmu_rollcall"
        home_dir.mkdir(parents=True, exist_ok=True)
        test_file = home_dir / ".test_write"
        try:
            test_file.touch()
            test_file.unlink()
            return home_dir
        except (OSError, PermissionError):
            pass
    except (OSError, PermissionError, RuntimeError):
        pass
    return Path.cwd() / ".xmu_rollcall"


CONFIG_DIR = _get_config_dir()
CONFIG_FILE = CONFIG_DIR / "config.json"


def _ensure_config_dir():
    """Ensure the config directory exists."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)


def _load_config():
    """Load the config file as a Python dict."""
    _ensure_config_dir()
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"accounts": []}


def _save_config(config):
    """Save the config dict to file."""
    _ensure_config_dir()
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def save_account(nickname, username, password, color_hex):
    """
    Save a new account to config.

    Args:
        nickname: Display name string
        username: Student/staff ID string
        password: Password string
        color_hex: Hex color string (e.g. "#FF0000")

    Returns:
        JSON string: {"success": true, "account_id": "uuid-string"}
    """
    try:
        config = _load_config()
        account_id = str(uuid.uuid4())
        new_account = {
            "id": account_id,
            "nickname": nickname,
            "username": username,
            "password": password,
            "color_hex": color_hex,
        }
        config["accounts"].append(new_account)
        _save_config(config)
        return json.dumps({"success": True, "account_id": account_id})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})


def load_accounts():
    """
    Load all saved accounts.

    Returns:
        JSON string:
        {
            "success": true,
            "accounts": [
                {
                    "id": "uuid-string",
                    "nickname": "...",
                    "username": "...",
                    "password": "...",
                    "color_hex": "#FF0000"
                },
                ...
            ]
        }
    """
    try:
        config = _load_config()
        accounts = config.get("accounts", [])
        return json.dumps({"success": True, "accounts": accounts})
    except Exception as e:
        return json.dumps({"success": False, "accounts": [], "error": str(e)})


def delete_account(account_id):
    """
    Delete an account by ID.

    Args:
        account_id: UUID string of the account to delete

    Returns:
        JSON string: {"success": true/false, "error": "..."}
    """
    try:
        config = _load_config()
        accounts = config.get("accounts", [])
        original_count = len(accounts)
        config["accounts"] = [a for a in accounts if a.get("id") != account_id]

        if len(config["accounts"]) == original_count:
            return json.dumps({"success": False, "error": "Account not found."})

        # Also delete cached cookies if they exist
        cookies_path = CONFIG_DIR / f"{account_id}.json"
        if cookies_path.exists():
            cookies_path.unlink()

        _save_config(config)
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})


def save_cookies(account_id, cookies_json):
    """
    Save session cookies for an account.

    Args:
        account_id: UUID string
        cookies_json: JSON string of cookie dict

    Returns:
        JSON string: {"success": true/false}
    """
    try:
        _ensure_config_dir()
        path = CONFIG_DIR / f"{account_id}.json"
        with open(path, "w", encoding="utf-8") as f:
            f.write(cookies_json)
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})


def load_cookies(account_id):
    """
    Load cached session cookies for an account.

    Args:
        account_id: UUID string

    Returns:
        JSON string: {"success": true/false, "cookies": "..."}
    """
    try:
        path = CONFIG_DIR / f"{account_id}.json"
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                cookies = f.read()
            return json.dumps({"success": True, "cookies": cookies})
        return json.dumps({"success": False, "error": "No cached cookies."})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})


def update_account(account_id, nickname=None, username=None, password=None, color_hex=None):
    """
    Update fields of an existing account.

    Args:
        account_id: UUID string
        nickname, username, password, color_hex: Optional fields to update

    Returns:
        JSON string: {"success": true/false, "error": "..."}
    """
    try:
        config = _load_config()
        for acc in config.get("accounts", []):
            if acc.get("id") == account_id:
                if nickname is not None:
                    acc["nickname"] = nickname
                if username is not None:
                    acc["username"] = username
                if password is not None:
                    acc["password"] = password
                if color_hex is not None:
                    acc["color_hex"] = color_hex
                _save_config(config)
                return json.dumps({"success": True})
        return json.dumps({"success": False, "error": "Account not found."})
    except Exception as e:
        return json.dumps({"success": False, "error": str(e)})
