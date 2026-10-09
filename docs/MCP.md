# Connect an AI client

Agora ships with a standalone stdio MCP server. It shares the native app's SQLite library and runs while the app is closed. Install the app into `/Applications` or `~/Applications` before registering the helper; don't use a mounted disk-image or temporary build path.

## Claude Desktop and other JSON clients

Merge this entry into the client's existing `mcpServers` object, preserving other servers, then restart the client:

```json
{
  "mcpServers": {
    "agora-local": {
      "command": "/Applications/Agora.app/Contents/MacOS/AgoraMCP",
      "args": []
    }
  }
}
```

For a different library, add `"env": {"AGORA_DATA_DIR": "/absolute/path/to/library"}` to the server entry. Configure the app with the same directory to see the same records.

## TOML clients

```toml
[mcp_servers.agora-local]
command = "/Applications/Agora.app/Contents/MacOS/AgoraMCP"
```

## Tools

| Tool | Purpose |
|---|---|
| `get_overview` | Counts, overdue promises, due-today items, waiting-on-others and recent interactions |
| `list_contacts` | Search names, emails, companies and tags; pagination |
| `get_contact` | Profile, history and commitments |
| `create_contact` | Add a person |
| `update_contact` | Patch a profile using `expectedRevision` |
| `log_interaction` | Record an email, meeting, call, message or note |
| `list_commitments` | Filter by person, status, direction, deadline or overdue flag; pagination |
| `create_commitment` | Register a promise and optional source interaction |
| `update_commitment` | Edit, complete, reopen or cancel with revision protection |
| `capture_email` | Atomic, idempotent email and promise capture |

Dates use local `YYYY-MM-DD` days. Interaction times use Unix seconds. `direction: "i_owe"` means you promised the other person; `"they_owe"` means you are waiting on them. Status is `open`, `done` or `cancelled`. Priority is `normal` or `high`.

Create a promise:

```json
{
  "contactId": "the-id-returned-by-list_contacts",
  "title": "Send the project proposal",
  "dueDate": "2026-10-16",
  "direction": "i_owe",
  "priority": "high"
}
```

Mark it kept using the revision returned by creation or discovery:

```json
{
  "id": "the-commitment-id",
  "expectedRevision": 1,
  "fields": {"status": "done"}
}
```

Use `{"dueDate": null}` inside `fields` to clear a deadline. If a write is rejected because the record changed elsewhere, fetch the latest record and reconcile the intended change before retrying.

The server writes only protocol JSON to stdout; diagnostics use stderr. It exposes no internet endpoint. A cloud-hosted MCP client cannot directly run the local helper. The connected local client has access to the library, and its model provider's data handling applies to the records the client sends.
