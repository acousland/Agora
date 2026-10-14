# Agora application review — 14 October 2026

Scope: native SwiftUI app, shared SQLite store, stdio MCP helper, Outlook receiver and add-in source, build/signing scripts, published Sparkle feed and local AI-client setup. This is a source review with targeted runtime verification, not an independent penetration test.

## Findings addressed in 1.1.0

| Priority | Finding | Resolution |
| --- | --- | --- |
| High | Agora could copy an MCP snippet but could not register itself with installed clients. | Added explicit setup for Codex / ChatGPT, Claude Desktop and Claude Code. Setup preserves unrelated settings, creates private backups, reports configuration status, and rejects temporary helper paths. |
| Medium | Copied MCP configuration omitted a custom library, allowing the app and assistant to open different databases. | Setup and copied configuration explicitly include the app's library through `AGORA_DATA_DIR`. |
| Medium | Update signing verified with the signing key itself, without independently checking the public key embedded in installed apps. | Publication now verifies the archive with CryptoKit against `Assets/sparkle-public-key` and requires a Developer ID identity. |
| Medium | Imported contact emails were validated after normalization but inserted without that normalization. Whitespace could bypass email uniqueness and create inconsistent records. | Imported profiles now normalize email, name, company, role, tags and notes before insertion; malformed tags and revision overflow are rejected. Regression tests cover duplicate rollback. |
| Medium | MCP discovery did not describe editable fields inside update operations. | Added explicit nested schemas, enum values, pagination bounds, nullable deadlines and read/write safety annotations. |
| Low | Sparkle supported background checks, but the app exposed no update preferences. | Connections now offers automatic checks, automatic download / installation and a manual check with availability tracking. Automatic installation remains a user preference. |
| Low | The MCP handshake always advertised 1.0.0 and overstated data privacy. | The helper reports its bundled app version and explains that the connected client can send records to its model provider. |
| Low | Rotating the Outlook pairing key before its first creation failed. Creating contacts silently dropped tags beyond the limit. | Rotation creates a key when necessary; contact creation rejects more than 30 tags consistently. |

## Verification

- `swift test`: 14 tests pass, covering shared writers, stale revisions, atomic capture and rollback, imports, uniqueness, backups, key rotation, JSON configuration preservation, malformed settings and Codex registration through the real CLI with an isolated home.
- `scripts/smoke-mcp.py`: all ten tools exercised over the real stdio transport, with an isolated empty library. Includes modern experimental initialization capabilities, discovery, search, pagination, profile edits, source-linked promises, completion/reopening, null deadlines, idempotent capture, rollback, invalid argument errors, continued service after errors, and visibility to a separate SQLite connection.
- The release-built helper passes the same MCP smoke test.
- The existing public 1.0.0 DMG downloads successfully and its Ed25519 signature verifies independently against the public key shipped in Agora. The appcast uses HTTPS and has the matching archive length. The release pipeline applies the same check to new releases before upload.
- The native Connections screen was rendered by Agora's SwiftUI/AppKit preview harness and visually inspected, including the MCP setup rows and update controls. Interactive UI automation was unavailable because access to Agora was not approved by the computer-use tool.
- The native HTTPS receiver passes `scripts/smoke-outlook.py` using a disposable library and test certificate: certificate validation, authentication, Host/Origin restrictions, static assets, path restrictions, atomic capture, duplicate protection and invalid-date rejection. The Outlook manifest parses as XML. No Outlook resource or manifest was changed in this review.
- A working Apple notarisation Keychain profile is available. Release publication submits and staples both the app and DMG and stops if notarisation fails.

## Limits and follow-up checks

- Configuration status in Agora describes saved client settings. Restart the AI client after setup or an app update, then check its MCP status. Client policy and project overrides can disable a user-level registration. Setup is explicit; merely opening Agora never changes client settings.
- ChatGPT desktop, Codex CLI and the IDE extension share MCP configuration for the same local Codex host. Hosted web/cloud chats do not read this Mac's configuration. See [OpenAI's MCP documentation](https://learn.chatgpt.com/docs/extend/mcp) and [Claude Code's documentation](https://code.claude.com/docs/en/mcp).
- A complete Sparkle replacement/relaunch of the user's running app was not exercised interactively. The feed, archive signatures, bundle configuration, signing and notarisation are checked separately.
- Outlook sideloading and a real signed-in mailbox capture still require account-level verification. This review exercised the local receiver without accessing a mailbox.
- Read operations load the library into memory before filtering or pagination. This is reasonable for a personal library; a large-library performance test and SQL-backed pagination would be the next scaling work. The active native app refreshes shared changes every three seconds.
- SQLite data is local and protected with filesystem permissions, but is not application-level encrypted. Exported JSON contains full email bodies. AI-client data handling applies to records retrieved through MCP. No private library, token, certificate or signing key is included in the repository or release assets.
