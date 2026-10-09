"""Exercise the real stdio helper against an isolated SQLite library."""
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/AgoraMCP").resolve()
with tempfile.TemporaryDirectory(prefix="agora-mcp-") as directory:
    process = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env={**os.environ, "AGORA_DATA_DIR": directory})
    replies = queue.Queue()
    def reader():
        for line in process.stdout:
            replies.put(json.loads(line))
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
        assert len(tools) == 10
        person = call("create_contact", {"name": "Test Contact", "email": "test@example.com"})
        note = call("log_interaction", {"contactId": person["id"], "kind": "call", "subject": "Testing a promise"})
        promise = call("create_commitment", {"contactId": person["id"], "title": "Send the proposal", "interactionId": note["id"], "dueDate": "2026-10-10"})
        assert call("get_contact", {"id": person["id"]})["commitments"][0]["id"] == promise["id"]
        done = call("update_commitment", {"id": promise["id"], "expectedRevision": 1, "fields": {"status": "done"}})
        assert done["status"] == "done" and done["revision"] == 2
        assert call("list_commitments", {"status": "done"})["total"] == 1
        assert call("get_overview", {})["open"] == 0
        stale = request("tools/call", {"name": "update_commitment", "arguments": {"id": promise["id"], "expectedRevision": 1, "fields": {"status": "open"}}})
        assert stale.get("isError")
        print("MCP smoke passed: initialise, discovery, contacts, interactions, linked promises, filters, completion, stale-write protection.")
    finally:
        process.stdin.close()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
