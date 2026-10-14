"""Exercise a running native HTTPS receiver using only disposable test data."""
import http.client
import json
import pathlib
import ssl
import sys

directory = pathlib.Path(sys.argv[1])
port = int(sys.argv[2]) if len(sys.argv) > 2 else 3848
profile_id = None
context = ssl.create_default_context(cafile=str(directory / "localhost.crt"))
token = (directory / "outlook-token").read_text()
def request(method, path, payload=None, *, auth=True, origin=None, host=None, profile=True):
    connection = http.client.HTTPSConnection("localhost", port, context=context, timeout=10)
    headers = {"Content-Type": "application/json"}
    if auth: headers["Authorization"] = "Bearer " + token
    if origin: headers["Origin"] = origin
    if host: headers["Host"] = host
    if profile and profile_id: headers["X-Agora-Profile"] = profile_id if profile is True else profile
    body = json.dumps(payload) if payload is not None else None
    connection.request(method, path, body=body, headers=headers)
    response = connection.getresponse()
    result = response.status, response.read()
    connection.close()
    return result

assert request("GET", "/health", auth=False)[0] == 200
assert request("GET", "/api/ping", auth=False)[0] == 401
assert request("GET", "/api/ping?client=outlook", auth=False)[0] == 401
assert request("GET", "/api/ping", origin="https://evil.example")[0] == 403
assert request("GET", "/api/ping", host="evil.example:3848")[0] == 403
assert request("GET", "/api/ping")[0] == 200
profile_id = json.loads(request("GET", "/api/ping")[1])["profile"]["id"]
assert json.loads(request("GET", "/profile", auth=False)[1])["id"] == profile_id
assert request("GET", "/api/ping?client=outlook")[0] == 200
taskpane = request("GET", "/taskpane.html", auth=False)
for path in ["/taskpane.html?_host_Info=Outlook%24Mac%2416.113.4%24en-US", "/taskpane.html?et=&_host_Info=Outlook$Mac&locale=en-AU", "/?_host_Info=Outlook%24Mac", "/taskpane.html?"]:
    assert request("GET", path, auth=False) == taskpane, path
for asset in ["taskpane.html", "taskpane.js", "taskpane.css", "manifest.xml", "icon-16.png", "icon-32.png", "icon-64.png", "icon-80.png"]:
    assert request("GET", "/" + asset, auth=False)[0] == 200, asset
    assert request("GET", "/" + asset + "?v=1", auth=False) == request("GET", "/" + asset, auth=False), asset
assert request("GET", "/../outlook-token", auth=False)[0] == 404
for path in ["/../outlook-token?file=taskpane.html", "/%2e%2e/outlook-token?file=taskpane.html", "/missing.html?file=taskpane.html"]:
    assert request("GET", path, auth=False)[0] == 404, path
payload = {"contactName": "Outlook Test", "contactEmail": "outlook-test@example.com", "subject": "A real HTTPS capture test", "body": "I promised to share the proposal.", "externalId": "agora-https-smoke", "commitments": [{"title": "Share the proposal", "dueDate": "2026-10-16", "direction": "i_owe"}]}
assert request("POST", "/api/capture", payload, profile=False)[0] == 409
assert request("POST", "/api/capture", payload, profile="another-profile")[0] == 409
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
print("Outlook HTTPS smoke passed: TLS certificate, pairing, Origin/Host validation, assets with Office URL parameters, path restrictions, atomic capture, duplicate protection, invalid-date rejection.")
