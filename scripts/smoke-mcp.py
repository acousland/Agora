"""Exercise the real stdio helper against an isolated SQLite library."""
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading
import sqlite3

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/AgoraMCP").resolve()
with tempfile.TemporaryDirectory(prefix="agora-mcp-") as directory:
    process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={**os.environ, "AGORA_DATA_DIR": directory})
    replies = queue.Queue()
    def reader():
        for line in process.stdout:
            try: replies.put(json.loads(line))
            except json.JSONDecodeError: replies.put({"invalid_stdout": line})
    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    sequence = 0
    def request(method, params):
        global sequence
        sequence += 1
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": sequence, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        while True:
            reply = replies.get(timeout=15)
            assert "invalid_stdout" not in reply, "Non-protocol output on stdout"
            if reply.get("id") == sequence:
                assert "error" not in reply, reply
                return reply["result"]
    def call(name, arguments):
        result = request("tools/call", {"name": name, "arguments": arguments})
        assert not result.get("isError"), result
        return json.loads(result["content"][0]["text"])
    try:
        init = request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {"experimental": {"modernClient": {"enabled": True}}}, "clientInfo": {"name": "agora-smoke", "version": "1"}})
        assert init["serverInfo"]["name"] == "Agora"
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n"); process.stdin.flush()
        tools = request("tools/list", {})["tools"]
        assert {tool["name"] for tool in tools} == {"get_overview", "list_contacts", "get_contact", "create_contact", "update_contact", "log_interaction", "list_commitments", "create_commitment", "update_commitment", "capture_email"}
        schemas = {tool["name"]: tool["inputSchema"] for tool in tools}
        assert "status" in schemas["update_commitment"]["properties"]["fields"]["properties"]
        assert "null" in schemas["update_commitment"]["properties"]["fields"]["properties"]["dueDate"]["type"]
        assert call("list_contacts", {})["total"] == 0, "A new library must start empty"
        assert call("get_overview", {})["contacts"] == 0
        person = call("create_contact", {"name": "Test Contact", "email": "test@example.com"})
        updated = call("update_contact", {"id": person["id"], "expectedRevision": 1, "fields": {"company": "Example", "tags": ["Test"]}})
        assert updated["company"] == "Example" and updated["revision"] == 2
        assert call("list_contacts", {"search": "Example", "limit": 1})["total"] == 1
        note = call("log_interaction", {"contactId": person["id"], "kind": "call", "subject": "Testing a promise"})
        promise = call("create_commitment", {"contactId": person["id"], "title": "Send the proposal", "interactionId": note["id"], "dueDate": "2026-10-10"})
        assert call("get_contact", {"id": person["id"]})["commitments"][0]["id"] == promise["id"]
        done = call("update_commitment", {"id": promise["id"], "expectedRevision": 1, "fields": {"status": "done"}})
        assert done["status"] == "done" and done["revision"] == 2
        assert call("list_commitments", {"status": "done"})["total"] == 1
        assert call("get_overview", {})["open"] == 0
        stale = request("tools/call", {"name": "update_commitment", "arguments": {"id": promise["id"], "expectedRevision": 1, "fields": {"status": "open"}}})
        assert stale.get("isError")
        reopened = call("update_commitment", {"id": promise["id"], "expectedRevision": 2, "fields": {"status": "open", "dueDate": None}})
        assert reopened.get("dueDate") is None and reopened.get("completedAt") is None
        assert call("list_commitments", {"contactId": person["id"], "status": "open"})["total"] == 1
        payload = {"contactName": "Email Contact", "contactEmail": "email@example.com", "subject": "A promise", "externalId": "smoke-message", "commitments": [{"title": "Send details", "direction": "they_owe"}]}
        first = call("capture_email", payload)
        duplicate = call("capture_email", payload)
        assert duplicate["alreadySaved"] and duplicate["interactionId"] == first["interactionId"] and duplicate["commitmentIds"] == first["commitmentIds"]
        assert call("list_contacts", {"limit": 1})["nextOffset"] == 1
        assert call("list_contacts", {"limit": 1, "offset": 1})["nextOffset"] is None
        invalid = {**payload, "contactEmail": "rollback@example.com", "externalId": "bad-message", "commitments": [{"title": "Good"}, {"title": "Bad date", "dueDate": "2026-02-30"}]}
        assert request("tools/call", {"name": "capture_email", "arguments": invalid}).get("isError")
        assert call("list_contacts", {"search": "rollback@example.com"})["total"] == 0
        for name, arguments in [("list_contacts", {"limit": True}), ("list_contacts", {"limit": 0}), ("create_contact", {"name": "Bad", "tags": [1]}), ("get_contact", {"id": "missing"}), ("unknown", {}), ("update_contact", {"id": person["id"], "expectedRevision": 2, "fields": {"id": "changed"}})]:
            assert request("tools/call", {"name": name, "arguments": arguments}).get("isError"), name
        # A separate SQLite connection sees committed MCP writes while the helper runs.
        with sqlite3.connect(pathlib.Path(directory) / "agora.sqlite") as database:
            assert database.execute("SELECT count(*) FROM contacts").fetchone()[0] == 2
            assert database.execute("SELECT count(*) FROM interactions").fetchone()[0] == 2
        assert call("get_overview", {})["contacts"] == 2, "Errors must not terminate the helper"
        print("MCP smoke passed: all 10 tools, schemas, empty library, search, pagination, profile revisions, linked promises, completion/reopening, null deadlines, atomic email capture, duplicate protection, rollback, invalid arguments, shared storage and recovery after errors.")
    finally:
        process.stdin.close()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)

subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("smoke-profiles.py")), str(binary)], check=True)
