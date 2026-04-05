"""
XMU Rollcall monitor module for Swift bridge interop.
Single-shot polling function — Swift controls the timer loop.
All functions accept/return JSON strings for easy Swift bridging.
"""

import json
import requests


BASE_URL = "https://lnt.xmu.edu.cn"
ROLLCALLS_URL = f"{BASE_URL}/api/radar/rollcalls"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json",
    "Accept-Language": "zh-CN,zh;q=0.9",
}


def _make_session_from_cookies(cookies_json):
    """Reconstruct a requests.Session from serialized cookies JSON."""
    cookie_dict = json.loads(cookies_json)
    session = requests.Session()
    session.cookies = requests.utils.cookiejar_from_dict(cookie_dict)
    session.headers.update(HEADERS)
    return session


def poll_rollcalls(cookies_json):
    """
    Single-shot poll for active rollcalls.

    Args:
        cookies_json: JSON string of cookie dict

    Returns:
        JSON string:
        {
            "success": true/false,
            "rollcalls": [
                {
                    "rollcall_id": 12345,
                    "course_title": "...",
                    "created_by_name": "...",
                    "department_name": "...",
                    "is_expired": false,
                    "is_number": true,
                    "is_radar": false,
                    "rollcall_status": "...",
                    "scored": 0,
                    "status": "absent"
                },
                ...
            ],
            "error": "..."  // only on failure
        }
    """
    try:
        session = _make_session_from_cookies(cookies_json)
        resp = session.get(ROLLCALLS_URL, headers=HEADERS, timeout=10)

        if resp.status_code == 200:
            data = resp.json()
            raw_rollcalls = data.get("rollcalls", [])
            rollcalls = []
            for rc in raw_rollcalls:
                rollcalls.append({
                    "rollcall_id": rc.get("rollcall_id"),
                    "course_title": rc.get("course_title", ""),
                    "created_by_name": rc.get("created_by_name", ""),
                    "department_name": rc.get("department_name", ""),
                    "is_expired": rc.get("is_expired", False),
                    "is_number": rc.get("is_number", False),
                    "is_radar": rc.get("is_radar", False),
                    "rollcall_status": rc.get("rollcall_status", ""),
                    "scored": rc.get("scored", 0),
                    "status": rc.get("status", ""),
                })
            return json.dumps({
                "success": True,
                "rollcalls": rollcalls,
            })
        elif resp.status_code == 401:
            return json.dumps({
                "success": False,
                "rollcalls": [],
                "error": "Session expired. Please re-login.",
            })
        else:
            return json.dumps({
                "success": False,
                "rollcalls": [],
                "error": f"HTTP {resp.status_code}: {resp.text[:200]}",
            })

    except requests.exceptions.Timeout:
        return json.dumps({
            "success": False,
            "rollcalls": [],
            "error": "Request timed out.",
        })
    except requests.exceptions.ConnectionError:
        return json.dumps({
            "success": False,
            "rollcalls": [],
            "error": "Connection error. Check network.",
        })
    except Exception as e:
        return json.dumps({
            "success": False,
            "rollcalls": [],
            "error": str(e),
        })


def handle_rollcall(cookies_json, rollcall_json):
    """
    Process a single rollcall and attempt to answer it.

    Args:
        cookies_json: JSON string of cookie dict
        rollcall_json: JSON string of a single rollcall object

    Returns:
        JSON string:
        {
            "success": true/false,
            "type": "number" | "radar" | "qrcode",
            "result": "1234" | "24.xxx,118.xxx" | "",
            "error": "..."
        }
    """
    try:
        from xmu_verify import send_code, send_radar

        rc = json.loads(rollcall_json)
        rollcall_id = rc.get("rollcall_id")
        is_number = rc.get("is_number", False)
        is_radar = rc.get("is_radar", False)
        status = rc.get("status", "")

        if status == "on_call_fine":
            return json.dumps({
                "success": True,
                "type": "already_answered",
                "result": "Already answered",
                "error": "",
            })

        if is_radar:
            result_json = send_radar(cookies_json, rollcall_id)
            result = json.loads(result_json)
            if result["success"]:
                coords = f"{result['latitude']:.6f},{result['longitude']:.6f}"
                return json.dumps({
                    "success": True,
                    "type": "radar",
                    "result": coords,
                    "error": "",
                })
            else:
                return json.dumps({
                    "success": False,
                    "type": "radar",
                    "result": "",
                    "error": result.get("error", "Radar answer failed"),
                })

        elif is_number and not is_radar:
            if status == "absent":
                result_json = send_code(cookies_json, rollcall_id)
                result = json.loads(result_json)
                if result["success"]:
                    return json.dumps({
                        "success": True,
                        "type": "number",
                        "result": result["code"],
                        "error": "",
                    })
                else:
                    return json.dumps({
                        "success": False,
                        "type": "number",
                        "result": "",
                        "error": result.get("error", "Number code failed"),
                    })
            else:
                return json.dumps({
                    "success": True,
                    "type": "number",
                    "result": "Status: " + status,
                    "error": "",
                })

        else:
            # QR code rollcall — not supported
            return json.dumps({
                "success": False,
                "type": "qrcode",
                "result": "",
                "error": "QR code rollcall not supported.",
            })

    except Exception as e:
        return json.dumps({
            "success": False,
            "type": "unknown",
            "result": "",
            "error": str(e),
        })
