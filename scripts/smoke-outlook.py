"""Exercise a running native HTTPS receiver using only disposable test data."""
import http.client
import json
import pathlib
import ssl
import sys

directory = pathlib.Path(sys.argv[1])
context = ssl.create_default_context(cafile=str(directory / "localhost.crt"))
token = (directory / "outlook-token").read_text()
def request(method, path, payload=None, *, auth=True, origin=None, host=None):
    connection = http.client.HTTPSConnection("localhost", 3848, context=context, timeout=10)
    headers = {"Content-Type": "application/json"}
    if auth: headers["Authorization"] = "Bearer " + token
    if origin: headers["Origin"] = origin
    if host: headers["Host"] = host
    body = json.dumps(payload) if payload is not None else None
    connection.request(method, path, body=body, headers=headers)
    response = connection.getresponse()
    result = response.status, response.read()
    connection.close()
    return result

assert request("GET", "/health", auth=False)[0] == 200
assert request("GET", "/api/ping", auth=False)[0] == 401
assert request("GET", "/api/ping", origin="https://evil.example")[0] == 403
assert request("GET", "/api/ping", host="evil.example:3848")[0] == 403
assert request("GET", "/api/ping")[0] == 200
for asset in ["taskpane.html", "taskpane.js", "taskpane.css", "manifest.xml", "icon-16.png", "icon-32.png", "icon-64.png", "icon-80.png"]:
    assert request("GET", "/" + asset, auth=False)[0] == 200, asset
assert request("GET", "/../outlook-token", auth=False)[0] == 404
payload = {"contactName": "Outlook Test", "contactEmail": "outlook-test@example.com", "subject": "A real HTTPS capture test", "body": "I promised to share the proposal.", "externalId": "agora-https-smoke", "commitments": [{"title": "Share the proposal", "dueDate": "2026-10-16", "direction": "i_owe"}]}
status, body = request("POST", "/api/capture", payload)
assert status == 200, body
first = json.loads(body)
status, body = request("POST", "/api/capture", payload)
second = json.loads(body)
assert status == 200 and second["alreadySaved"]
assert first["interactionId"] == second["interactionId"] and first["commitmentIds"] == second["commitmentIds"]
payload["externalId"] = "agora-bad-https-smoke"
payload["contactEmail"] = "invalid-test@example.com"
payload["commitments"][0]["dueDate"] = "2026-02-30"
assert request("POST", "/api/capture", payload)[0] == 400
print("Outlook HTTPS smoke passed: TLS certificate, pairing, Origin/Host validation, assets, path restrictions, atomic capture, duplicate protection, invalid-date rejection.")
