import os
import json
import pathlib
import requests
from flask import Flask, request, jsonify
from flask_cors import CORS
from google.oauth2 import service_account
import google.auth.transport.requests as google_requests

app = Flask(__name__)
# CORS is helpful during local dev when your web app runs on a different port.
CORS(app, resources={r"/api/*": {"origins": "*"}})

# ======== CONFIG ========
# Set these via environment variables for safety, or hard-code while testing.
PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "graph-go-bd4f0")
SERVICE_ACCOUNT_FILE = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "service-account.json")
TOKENS_FILE = pathlib.Path("admin_tokens.json")

# FCM v1 endpoint
FCM_SEND_URL = f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send"
SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

# ======== TOKEN STORAGE (simple JSON file for now) ========
def _load_tokens() -> set[str]:
    if TOKENS_FILE.exists():
        try:
            return set(json.loads(TOKENS_FILE.read_text()))
        except Exception:
            return set()
    return set()

def _save_tokens(tokens: set[str]) -> None:
    TOKENS_FILE.write_text(json.dumps(list(tokens), indent=2))

ADMIN_TOKENS: set[str] = _load_tokens()

# ======== AUTH (get OAuth2 access token from Service Account) ========
def _get_access_token() -> str:
    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES
    )
    creds.refresh(google_requests.Request())
    return creds.token

# ======== FCM SENDER (HTTP v1) ========
def send_to_tokens(tokens: set[str], data: dict) -> tuple[int, str]:
    if not tokens:
        return 200, '{"info":"no admin tokens registered"}'

    access_token = _get_access_token()
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=UTF-8",
    }

    title = data.get("title", "Update")
    body = data.get("body", "")

    last_status = 200
    last_text = "ok"
    for token in tokens:
        message = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {k: str(v) for k, v in data.items()},
            }
        }
        r = requests.post(FCM_SEND_URL, headers=headers, data=json.dumps(message))
        last_status, last_text = r.status_code, r.text

    return last_status, last_text

# ======== ROUTES ========

@app.post("/api/notifications/register")
def register_token():
    p = request.get_json(force=True)
    token = p["token"]
    role = p.get("role", "admin")

    if role == "admin":
        ADMIN_TOKENS.add(token)
        _save_tokens(ADMIN_TOKENS)

    return jsonify({"ok": True, "admin_tokens": len(ADMIN_TOKENS)})

@app.post("/api/notify/route-status")
def route_status():
    data = request.get_json(silent=True) or {}

    route_id = (data.get("routeId") or "").strip()
    status   = (data.get("status") or "").strip().upper()
    driver_id = (data.get("driverId") or "").strip()

    if not route_id or status not in {"COMPLETED", "DENIED"}:
        return jsonify({
            "ok": False,
            "error": "Invalid payload. Expect routeId (str), status in {COMPLETED,DENIED}, driverId (str).",
            "got": data
        }), 400

    if not ADMIN_TOKENS:
        return jsonify({"ok": True, "sent": 0, "note": "No admin tokens registered."}), 200

    title = f"Route {status.title()}"
    if status == "COMPLETED":
        body  = f"Driver {driver_id} completed route {route_id}."
    else:
        body  = f"Driver {driver_id} denied route {route_id}."

    payload = {
        "type": "ROUTE_STATUS",
        "status": status,
        "routeId": route_id,
        "driverId": driver_id,
        "url": "/admin-dashboard?routeId=" + route_id,
        "title": title,
        "body": body
    }

    try:
        code, text = send_to_tokens(ADMIN_TOKENS, payload)
        return jsonify({"code": code, "response": text})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
