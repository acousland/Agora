# Connect an AI client

Agora ships with a standalone stdio MCP server. It opens the selected profile's SQLite library and runs while the app is closed. Install the app into `/Applications` or `~/Applications` before registering the helper; don't use a mounted disk-image or temporary build path.

## Automatic setup

Open **Connections** and select the setup button for **Codex / ChatGPT**, **Claude Desktop** or **Claude Code**. Quit and reopen that client after setup. Agora adds `agora-local`, preserves unrelated configuration and servers, and saves a private `agora-backup-…` copy beside existing configuration files. Setup explicitly records `AGORA_PROFILE_ROOT` so new connections open the selected profile. Set up an older fixed-library connection again to enable profiles.

Each MCP session stays bound to the profile selected when it starts. Its initialization instructions identify that profile. If the selection changes, both reads and writes from the old session are rejected until the client reconnects. Reconnect and start a new AI conversation when switching worlds; reconnecting does not erase records already present in a client's chat history. A file lock serializes profile switches with operations, preventing a switch from redirecting a write partway through.

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

Set `AGORA_PROFILE_ROOT` on the setup command for a custom profile root. An explicit `AGORA_DATA_DIR` retains fixed single-library behavior for existing integrations and isolated tools. Do not set both. Setup does not require the app to run, does not seed records, and writes its confirmation to stderr. App updates replace the helper at the same path, so configuration survives updates; restart the client to launch the new helper.

Connections shows a green **Configured** checkmark when the saved helper path, arguments and profile root match this installed copy of Agora. Missing or fixed-library settings show an amber badge; unreadable settings show a red warning. Use **Check configuration** to recheck. Status also refreshes after setup and when Agora becomes active. The indicator confirms saved configuration; restart the client after setup or a profile switch and use its MCP screen to confirm the live connection.

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

For a different profile root, add `"env": {"AGORA_PROFILE_ROOT": "/absolute/path/to/profile-root"}` to the server entry. Launch the native app with `AGORA_DATA_DIR` set to the same root. Omitting both environment variables uses the default profile root. An explicit `AGORA_DATA_DIR` on the helper selects a fixed library and does not follow profile switches.

## TOML clients

```toml
[mcp_servers.agora-local]
command = "/Applications/Agora.app/Contents/MacOS/AgoraMCP"
```

## Tools

Merged people can include `alternateEmails` in their profile. Contact search and email capture recognise these addresses. Update operations preserve them; merging and deletion are available in the native app's People menu. A retained duplicate interaction may include `duplicateExternalId`, preserving email-capture deduplication after a merge.

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
