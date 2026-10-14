"""Check profile isolation over real MCP sessions, including a running stale client."""
import fcntl
import json
import os
import pathlib
import queue
import sqlite3
import subprocess
import sys
import tempfile
import threading
import uuid

binary = pathlib.Path(sys.argv[1]).resolve()

class Client:
    def __init__(self, root):
        env = dict(os.environ, AGORA_PROFILE_ROOT=str(root))
        env.pop("AGORA_DATA_DIR", None)
        self.process = subprocess.Popen([str(binary)], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.replies = queue.Queue()
        self.sequence = 0
        def read():
            for line in self.process.stdout:
                try: self.replies.put(json.loads(line))
                except json.JSONDecodeError: self.replies.put({"invalid_stdout": line})
        threading.Thread(target=read, daemon=True).start()
        self.info = self.request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "profile-smoke", "version": "1"}})
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.process.stdin.flush()
    def request(self, method, params):
        self.sequence += 1
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.sequence, "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        while True:
            reply = self.replies.get(timeout=15)
            assert "invalid_stdout" not in reply, reply
            if reply.get("id") == self.sequence:
                assert "error" not in reply, reply
                return reply["result"]
    def call(self, name, args=None, error=False):
        result = self.request("tools/call", {"name": name, "arguments": args or {}})
        assert bool(result.get("isError")) == error, result
        return result["content"][0]["text"] if error else json.loads(result["content"][0]["text"])
    def close(self):
        self.process.stdin.close()
        try: self.process.wait(timeout=5)
        except subprocess.TimeoutExpired: self.process.terminate(); self.process.wait(timeout=5)

with tempfile.TemporaryDirectory(prefix="agora-mcp-profiles-") as name:
    root = pathlib.Path(name)
    settings = {"schemaVersion": 1, "activeID": "default", "profiles": [{"id": "default", "name": "Work"}, {"id": str(uuid.uuid4()), "name": "University"}]}
    (root / "profiles.json").write_text(json.dumps(settings))
    (root / "profiles.json").chmod(0o600)
    clients = []
    def select(profile_id):
        with (root / ".profiles.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            settings["activeID"] = profile_id
            with tempfile.NamedTemporaryFile(mode="w", dir=root, delete=False) as temporary: json.dump(settings, temporary)
            os.replace(temporary.name, root / "profiles.json")
    try:
        work = Client(root); clients.append(work)
        assert "Work profile" in work.info["instructions"]
        person = work.call("create_contact", {"name": "Work person", "email": "shared@example.com"})
        source = work.call("log_interaction", {"contactId": person["id"], "kind": "meeting", "subject": "Work meeting"})
        work.call("create_commitment", {"contactId": person["id"], "title": "Work promise", "interactionId": source["id"]})
        select(settings["profiles"][1]["id"])
        for tool, args in [("get_overview", {}), ("create_contact", {"name": "Wrong world"}), ("capture_email", {"contactName": "Wrong world", "contactEmail": "wrong@example.com", "subject": "Wrong", "externalId": "wrong-world"})]:
            assert "profile changed" in work.call(tool, args, error=True)
        university = Client(root); clients.append(university)
        assert "University profile" in university.info["instructions"]
        assert university.call("get_overview")["contacts"] == 0
        assert university.call("list_commitments")["total"] == 0
        university.call("get_contact", {"id": person["id"]}, error=True)
        university.call("create_contact", {"name": "University person", "email": "shared@example.com"})
        assert university.call("get_overview")["contacts"] == 1
        # A third client reconnects to the selected profile, even with the app closed.
        reconnected = Client(root); clients.append(reconnected)
        assert reconnected.call("list_contacts")["contacts"][0]["name"] == "University person"
        select("default")
        assert "profile changed" in university.call("get_overview", error=True)
        assert work.call("list_contacts")["contacts"][0]["name"] == "Work person"
        assert work.call("list_commitments")["total"] == 1
        with sqlite3.connect(root / "agora.sqlite") as database:
            assert database.execute("SELECT count(*) FROM contacts").fetchone()[0] == 1
        print("MCP profile smoke passed: selected profile at connection, app-independent libraries, isolated same-email contacts, stale reads and writes rejected, reconnect and Work history preserved.")
    finally:
        for client in clients: client.close()
