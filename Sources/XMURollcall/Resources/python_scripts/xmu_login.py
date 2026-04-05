"""
XMU Login module for Swift bridge interop.
Handles TronClass (type=3) login for the rollcall system.
All functions accept/return JSON strings for easy Swift bridging.
"""

import json
import requests
import base64
import random
import re
from Crypto.Cipher import AES
from urllib.parse import urlparse, parse_qs


# Constants
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9",
    "Referer": "https://ids.xmu.edu.cn/authserver/login",
}

COOKIES = {
    "org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE": "zh_CN"
}

LOGIN_URL = "https://ids.xmu.edu.cn/authserver/login"
AES_CHARS = "ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678"

BASE_URL = "https://lnt.xmu.edu.cn"
PROFILE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}


def _random_string(n):
    """Generate a random string of length n."""
    return "".join(random.choice(AES_CHARS) for _ in range(n))


def _pad(data):
    """PKCS7 padding."""
    pad_len = 16 - (len(data) % 16)
    return data + chr(pad_len) * pad_len


def _encrypt_password(password, salt):
    """Encrypt password using AES-CBC."""
    plaintext = _random_string(64) + password
    key = salt.encode()
    iv = _random_string(16).encode()
    cipher = AES.new(key, AES.MODE_CBC, iv)
    encrypted = cipher.encrypt(_pad(plaintext).encode())
    return base64.b64encode(encrypted).decode()


def _login_tronclass(username, password):
    """
    Login to XMU TronClass digital teaching platform via unified auth.
    Returns a requests.Session on success, None on failure.
    """
    url = "https://c-identity.xmu.edu.cn/auth/realms/xmu/protocol/openid-connect/auth"
    url_2 = "https://c-identity.xmu.edu.cn/auth/realms/xmu/protocol/openid-connect/token"
    url_3 = "https://lnt.xmu.edu.cn/api/login?login=access_token"

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/142.0.0.0 Mobile Safari/537.36"
        )
    }

    params = {
        "scope": "openid",
        "response_type": "code",
        "client_id": "TronClassH5",
        "redirect_uri": "https://c-mobile.xmu.edu.cn/identity-web-login-callback?_h5=true",
    }

    try:
        s = requests.Session()

        # Step 1: Get redirect
        headers_1 = s.get(url, headers=headers, params=params, allow_redirects=False).headers
        location = headers_1["location"]

        # Step 2: Follow redirect
        headers_2 = s.get(location, headers=headers, allow_redirects=False).headers
        location = headers_2["location"]

        # Step 3: Get login page
        res_3 = s.get(location, headers=headers, allow_redirects=False)
        html = res_3.text

        # Extract salt and execution
        salt = re.search(r'id="pwdEncryptSalt"\s+value="([^"]+)"', html).group(1)
        execution = re.search(r'name="execution"\s+value="([^"]+)"', html).group(1)

        # Encrypt password
        enc = _encrypt_password(password, salt)

        # Submit login form
        data = {
            "username": username,
            "password": enc,
            "captcha": "",
            "_eventId": "submit",
            "cllt": "userNameLogin",
            "dllt": "generalLogin",
            "lt": "",
            "execution": execution,
        }

        headers_4 = s.post(location, data=data, headers=headers, allow_redirects=False).headers
        location = headers_4["location"]

        headers_5 = s.get(location, headers=headers, allow_redirects=False).headers
        location = headers_5["location"]

        # Extract authorization code
        params_dict = parse_qs(urlparse(location).query)
        code = params_dict["code"][0]

        # Get access token
        data = {
            "client_id": "TronClassH5",
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "https://c-mobile.xmu.edu.cn/identity-web-login-callback?_h5=true",
            "scope": "openid",
        }

        res_6 = s.post(url_2, data=data, headers=headers).json()
        access_token = res_6["access_token"]

        # Final login
        data = {"access_token": access_token, "org_id": 1}

        if s.post(url_3, json=data).status_code == 200:
            return s
        else:
            return None

    except Exception as e:
        return None


def _session_to_cookies_json(session):
    """Serialize a requests.Session's cookies to a JSON string."""
    cookie_dict = requests.utils.dict_from_cookiejar(session.cookies)
    return json.dumps(cookie_dict)


def _get_profile_name(session):
    """Fetch user profile name from the session."""
    try:
        resp = session.get(f"{BASE_URL}/api/profile", headers=PROFILE_HEADERS)
        if resp.status_code == 200:
            data = resp.json()
            if isinstance(data, dict) and "name" in data:
                return data["name"]
    except Exception:
        pass
    return ""


def login(username, password):
    """
    Perform TronClass login and return JSON result.

    Args:
        username: Student/staff ID string
        password: Password string

    Returns:
        JSON string:
        {
            "success": true/false,
            "cookies": "...",     // serialized cookies JSON (only on success)
            "name": "...",        // user display name (only on success)
            "error": "..."        // error message (only on failure)
        }
    """
    try:
        session = _login_tronclass(username, password)
        if session is not None:
            cookies_json = _session_to_cookies_json(session)
            name = _get_profile_name(session)
            return json.dumps({
                "success": True,
                "cookies": cookies_json,
                "name": name,
            })
        else:
            return json.dumps({
                "success": False,
                "error": "Login failed. Please check your credentials.",
            })
    except Exception as e:
        return json.dumps({
            "success": False,
            "error": str(e),
        })


def verify_cookies(cookies_json):
    """
    Verify if stored cookies are still valid.

    Args:
        cookies_json: JSON string of cookie dict

    Returns:
        JSON string: {"valid": true/false, "name": "..."}
    """
    try:
        cookie_dict = json.loads(cookies_json)
        session = requests.Session()
        session.cookies = requests.utils.cookiejar_from_dict(cookie_dict)
        resp = session.get(f"{BASE_URL}/api/profile", headers=PROFILE_HEADERS)
        if resp.status_code == 200:
            data = resp.json()
            if isinstance(data, dict) and "name" in data:
                return json.dumps({"valid": True, "name": data["name"]})
    except Exception:
        pass
    return json.dumps({"valid": False, "name": ""})
