import os
import json
import pathlib
import requests
from flask import Flask, request, jsonify
from google.oauth2 import service_account
import google.auth.transport.requests as google_requests

app = Flask(__name__)

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
    """
    Creates a short-lived OAuth2 access token using your Firebase Service Account.
    SERVICE_ACCOUNT_FILE should point to the downloaded JSON credentials.
    """
    creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES
    )
    creds.refresh(google_requests.Request())
    return creds.token

# ======== FCM SENDER (HTTP v1) ========
def send_to_tokens(tokens: set[str], data: dict) -> tuple[int, str]:
    """
    Sends the same payload to each token (one by one).
    You can batch with 'tokens' topic later if you prefer.
    """
    if not tokens:
        return 200, '{"info":"no admin tokens registered"}'

    access_token = _get_access_token()
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=UTF-8",
    }

    # Optional: also mirror 'title/body' as a notification (some browsers display nicer)
    title = data.get("title", "Update")
    body = data.get("body", "")

    last_status = 200
    last_text = "ok"
    for token in tokens:
        message = {
            "message": {
                "token": token,
                "notification": {"title": title, "body": body},
                "data": {k: str(v) for k, v in data.items()},  # FCM requires string values in data
            }
        }
        r = requests.post(FCM_SEND_URL, headers=headers, data=json.dumps(message))
        last_status, last_text = r.status_code, r.text
        # You can add pruning logic here if response shows the token is invalid.
        # Example: if "UNREGISTERED", remove token from ADMIN_TOKENS and _save_tokens(ADMIN_TOKENS)

    return last_status, last_text

# ======== ROUTES ========

@app.post("/api/notifications/register")
def register_token():
    """
    Body: {"token": "...", "role":"admin"}
    Called by your Flutter web app after FirebaseMessaging.getToken().
    """
    p = request.get_json(force=True)
    token = p["token"]
    role = p.get("role", "admin")

    if role == "admin":
        ADMIN_TOKENS.add(token)
        _save_tokens(ADMIN_TOKENS)

    return jsonify({"ok": True, "admin_tokens": len(ADMIN_TOKENS)})

@app.get("/api/notifications/admin-count")
def admin_count():
    return jsonify({"admin_tokens": len(ADMIN_TOKENS)})

@app.post("/api/notify/route-status")
def route_status():
    """
    Body: {"routeId":"R_101","status":"COMPLETED" | "DENIED","driverId":"driver_12"}
    """
    p = request.get_json(force=True)
    route_id = p["routeId"]
    status = p["status"].upper()
    driver = p.get("driverId", "unknown")

    data = {
        "type": "ROUTE_STATUS",
        "routeId": route_id,
        "status": status,
        "title": "Route completed" if status == "COMPLETED" else "Route denied",
        "body": f"Driver {driver} {status.lower()} route {route_id}.",
        "url": f"/admin-dashboard?route={route_id}",
    }

    code, text = send_to_tokens(ADMIN_TOKENS, data)
    return jsonify({"code": code, "response": text})

@app.post("/api/notify/driver-message")
def driver_message():
    """
    Body: {"driverId":"driver_42","text":"Blocked street, rerouting."}
    """
    p = request.get_json(force=True)
    driver = p["driverId"]
    textmsg = p["text"]

    data = {
        "type": "MESSAGE",
        "from": driver,
        "title": f"Message from {driver}",
        "body": textmsg,
        "url": f"/admin-dashboard?inbox={driver}",
    }

    code, text = send_to_tokens(ADMIN_TOKENS, data)
    return jsonify({"code": code, "response": text})

@app.post("/api/notify/driver-alert")
def driver_alert():
    """
    Body: {"driverId":"driver_42","message":"Tire pressure low near Exit 17"}
    """
    p = request.get_json(force=True)
    driver = p["driverId"]
    msg = p["message"]

    data = {
        "type": "DRIVER_ALERT",
        "driverId": driver,
        "title": "Driver alert",
        "body": msg,
        "url": f"/admin-dashboard?driver={driver}",
    }

    code, text = send_to_tokens(ADMIN_TOKENS, data)
    return jsonify({"code": code, "response": text})

# --- FCM auth check: can we mint an OAuth token? ---
@app.get("/api/fcm/auth-check")
def fcm_auth_check():
    try:
        token = _get_access_token()          # uses your service-account.json
        # Don't return the whole token; just confirm it works.
        return jsonify({"ok": True, "token_prefix": token[:16] + "..."}), 200
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# --- Validate a message (no delivery) using HTTP v1 validate_only ---
@app.post("/api/fcm/validate")
def fcm_validate():
    """
    Body: {"token": "<FCM_REG_TOKEN>"}
    Uses validate_only to let Google check your credentials/permissions.
    """
    p = request.get_json(force=True)
    reg_token = p["token"]

    access_token = _get_access_token()
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; charset=UTF-8",
    }
    body = {
        "validate_only": True,  # << no push will actually be delivered
        "message": {
            "token": reg_token,
            "notification": {"title": "Test", "body": "Validation only"},
            "data": {"type": "HEALTHCHECK"}
        }
    }

    r = requests.post(FCM_SEND_URL, headers=headers, data=json.dumps(body))
    return jsonify({"status": r.status_code, "response": r.text}), r.status_code



if __name__ == "__main__":
    # For local testing
    app.run(host="0.0.0.0", port=5000, debug=True)
