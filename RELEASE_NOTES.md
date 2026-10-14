# Agora 1.1.0

- Set up local MCP connections for Codex / ChatGPT, Claude Desktop and Claude Code directly in Connections, with configuration backups and status reporting.
- Keep custom libraries connected to the correct MCP server, and prevent registration from temporary builds or mounted disk images.
- Add automatic update preferences for background checks and automatic download / installation.
- Describe editable MCP fields, nullable deadlines and tool safety hints in discovery; report the bundled app version during the MCP handshake.
- Expand MCP verification to cover all ten tools, error recovery, pagination, atomic capture and stale writes.
- Independently verify update signatures against the public key shipped in the app, and require Developer ID signing for publication.
- Normalize imported contact profiles before enforcing email uniqueness; reject invalid tags and revision overflow, and allow pairing-key rotation before first use.
- Prevent demo mode from adding sample data when the data directory is empty or points to the default private library.

This release is Developer ID signed and notarised by Apple. The app and disk image include stapled notarisation tickets.

Outlook capture passes the local authenticated HTTPS test. Installation and capture in a signed-in Outlook mailbox still need account-level verification.

# Agora 1.0.0

The first release of Agora, a native personal CRM for macOS 14 and later on Apple silicon.

- People profiles with contact details, tags and notes.
- Commitments with deadlines, priorities, source conversations and kept / cancelled states.
- Separate tracking for promises you made and promises made to you.
- A focused overview and searchable conversation timeline.
- Outlook for Mac task-pane add-in with explicit email capture and atomic commitment registration.
- Standalone local MCP server with ten tools, sharing the same SQLite library.
- Portable JSON export and import, and consistent SQLite backups.
- Sparkle updates from GitHub Releases, built and published directly from a Mac without GitHub Actions.

Outlook add-in installation requires a supported mailbox and manual sideloading through your Microsoft account. Real mailbox capture has not yet been verified in a signed-in Outlook session.
