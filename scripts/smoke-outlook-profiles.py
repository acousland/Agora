"""Exercise native profile switching while the isolated Outlook receiver is running."""
import fcntl
import http.client
import json
import os
import pathlib
import sqlite3
import ssl
import sys
import tempfile
import time

directory = pathlib.Path(sys.argv[1])
port = int(sys.argv[2])
context = ssl.create_default_context(cafile=str(directory / "localhost.crt"))
settings = json.loads((directory / "profiles.json").read_text())
work = next(profile for profile in settings["profiles"] if profile["id"] == "default")
university = next(profile for profile in settings["profiles"] if profile["name"] == "University")
work_token = (directory / "outlook-token").read_text()

def request(path, *, token=None, profile=None, payload=None):
    connection = http.client.HTTPSConnection("localhost", port, context=context, timeout=3)
    headers = {"Content-Type": "application/json"}
    if token: headers["Authorization"] = "Bearer " + token
    if profile: headers["X-Agora-Profile"] = profile
    connection.request("POST" if payload is not None else "GET", path, json.dumps(payload) if payload is not None else None, headers)
    response = connection.getresponse()
    result = response.status, response.read()
    connection.close()
    return result

def select(profile):
    with (directory / ".profiles.lock").open("r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        settings = json.loads((directory / "profiles.json").read_text())
        settings["activeID"] = profile["id"]
        with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as temporary:
            json.dump(settings, temporary)
        os.replace(temporary.name, directory / "profiles.json")
    for _ in range(60):
        status, body = request("/profile")
        if status == 200 and json.loads(body)["id"] == profile["id"]:
            return
        time.sleep(0.25)
    raise AssertionError("The native app did not switch the receiver to " + profile["name"])

def counts(path):
    with sqlite3.connect(path) as database:
        return tuple(database.execute("SELECT count(*) FROM " + table).fetchone()[0] for table in ["contacts", "interactions", "commitments"])

before = counts(directory / "agora.sqlite")
select(university)
payload = {"contactName": "Outlook Test", "contactEmail": "outlook-test@example.com", "subject": "University email", "externalId": "agora-https-smoke", "commitments": [{"title": "University follow-up"}]}
assert request("/api/capture", token=work_token, profile=work["id"], payload=payload)[0] == 401
university_directory = directory / "Profiles" / university["id"]
university_token = (university_directory / "outlook-token").read_text()
assert university_token != work_token
assert counts(university_directory / "agora.sqlite") == (0, 0, 0)
assert request("/api/capture", token=university_token, profile=work["id"], payload=payload)[0] == 409
assert request("/api/capture", token=university_token, payload=payload)[0] == 409
assert request("/api/capture", token=university_token, profile=university["id"], payload=payload)[0] == 200
assert counts(university_directory / "agora.sqlite") == (1, 1, 1)
assert counts(directory / "agora.sqlite") == before
select(work)
assert request("/api/ping", token=university_token)[0] == 401
assert request("/api/ping", token=work_token)[0] == 200
assert counts(directory / "agora.sqlite") == before
print("Outlook profile smoke passed: native switch, separate keys and databases, stale pairing rejected, destination header enforced, Work history preserved.")
