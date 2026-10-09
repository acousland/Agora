# Agora

Agora is a native macOS personal CRM with a shared SQLite core, an Office.js Outlook for Mac add-in and a standalone stdio MCP helper.

Keep private CRM libraries, tokens, certificates and signing keys out of source control. Default libraries must start empty; sample data is permitted only with an explicit `AGORA_DATA_DIR` and `--demo`.

Run `swift test` and `python3 scripts/smoke-mcp.py` for changes to storage or the MCP contract. Check the native app for UI changes. Validate the Outlook manifest and exercise the authenticated local receiver when changing the add-in.

The user has authorised a public GitHub repository, GitHub Releases built from this Mac without GitHub Actions, and Sparkle updates. Publish completed app changes to `acousland/Agora`: update `Assets/version` and `RELEASE_NOTES.md`, commit and push main, then run `scripts/publish-release.sh`. Never publish credentials or private data. Use an available notarisation Keychain profile through `AGORA_NOTARY_PROFILE`. If notarisation is unavailable, disclose the limitation; a signed unnotarised release requires the explicit script override `AGORA_ALLOW_UNNOTARIZED=1`.
