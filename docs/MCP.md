# Connect an AI client

Agora ships with a standalone stdio MCP server. It shares the native app's SQLite library and runs while the app is closed. Install the app into `/Applications` or `~/Applications` before registering the helper; don't use a mounted disk-image or temporary build path.

## Automatic setup

Open **Connections** and select the setup button for **Codex / ChatGPT**, **Claude Desktop** or **Claude Code**. Quit and reopen that client after setup. Agora adds `agora-local`, preserves unrelated configuration and servers, and saves a private `agora-backup-…` copy beside existing configuration files. Setup explicitly records `AGORA_DATA_DIR` so the client opens the same library as the app.

- Codex / ChatGPT: uses the official `codex mcp add` command, discovering either an installed CLI or the CLI bundled with ChatGPT desktop. The shared configuration is `~/.codex/config.toml` (or under `CODEX_HOME`). Verify with `codex mcp get agora-local --json`.
- Claude Desktop: merges into `~/Library/Application Support/Claude/claude_desktop_config.json`.
- Claude Code: merges into the user-scoped `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`). Project settings and managed policy can take precedence over user settings. Verify with `claude mcp get agora-local`.

The status in Agora reports saved configuration, rather than a live connection inside another app. The connected client's MCP status is the final check. ChatGPT desktop, Codex CLI and the IDE extension share configuration for the same local Codex host; web and cloud chats do not read local configuration. See [OpenAI's MCP guide](https://learn.chatgpt.com/docs/extend/mcp), [Claude Code's MCP guide](https://code.claude.com/docs/en/mcp) and [Claude Desktop's local-server guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers).

For command-line setup, the installed helper also accepts:

```sh
/Applications/Agora.app/Contents/MacOS/AgoraMCP --configure-client codex
/Applications/Agora.app/Contents/MacOS/AgoraMCP --configure-client claude-desktop
/Applications/Agora.app/Contents/MacOS/AgoraMCP --configure-client claude-code
```

Set `AGORA_DATA_DIR` on the setup command for a custom library. Setup does not require the app to run, does not seed a library, and writes its confirmation to stderr. App updates replace the helper at the same path, so configuration survives updates; restart the client to launch the new helper.

Connections shows a green **Configured** checkmark when the saved helper path, arguments and library match this installed copy of Agora. Missing or outdated settings show an amber badge; unreadable settings show a red warning. Use **Check configuration** to recheck. Status also refreshes after setup and when Agora becomes active. The indicator confirms saved configuration; restart the client after setup and use its MCP screen to confirm the live connection.

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
