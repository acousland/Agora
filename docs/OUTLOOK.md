# Outlook for Mac setup

The add-in is an Office.js task pane with an XML add-in-only manifest. It reads only the message you are viewing and saves it when you press **Save email to Agora**. It requests `ReadItem`, not mailbox-wide Graph access.

## Connect

1. Install and launch Agora.
2. Open **Connections → Outlook for Mac → Set up local HTTPS**. Approve any macOS certificate-trust prompt. A per-Mac certificate is generated with localhost and `127.0.0.1` subject alternative names and is trusted in your login Keychain. Its private identity is kept in a private Application Support directory.
3. Choose **Save manifest…**.
4. Open [Microsoft's sideloading page](https://aka.ms/olksideload) in your signed-in browser. Choose **My add-ins → Custom Addins → Add a custom add-in → Add from File** and select the manifest. Microsoft documents that this installation also appears in supported Outlook for Mac clients.
5. In Outlook for Mac, open a received or sent email and find **Agora / Save to Agora** in the Apps menu or ribbon.
6. Select your profile in Agora. Copy its pairing key from Connections and paste it into the task pane. Pairing is saved separately for each profile in the add-in's local storage.
7. Choose a person, add optional commitments, and save. Refresh Agora if it was in the background.

Each commitment can be a promise you made or a promise made to you, with an optional deadline and high priority. Saving is atomic: invalid promises prevent the contact, email and all promises from being partially saved. The source email remains attached to each commitment.

The pane displays **Saving to [profile]**. Switching profiles in Agora keeps the HTTPS listener available but changes its destination and pairing key. The pane checks the destination every five seconds while visible. On a switch it clears unsaved commitment drafts and asks you to connect and review the email; previously saved profile keys can be reused. An old token or mismatched destination header is rejected, including when a switch happens immediately before Save. The same email can be saved independently to Work and University.

## Troubleshooting

- **Task pane cannot load:** keep Agora open, check that Connections says it is listening, and visit `https://localhost:3848/health` from a browser on this Mac. Rerun HTTPS setup if the certificate has expired or trust was removed.
- **Task pane says “Not found”:** install Agora 1.2.1 or later, then quit and reopen Agora and close and reopen the Outlook task pane. Earlier versions rejected Office's extra URL parameters. The existing add-in installation can stay in place.
- **Connection unavailable / port in use:** quit another copy of Agora using port 3848 and relaunch.
- **Pairing rejected:** copy the latest key. Rotating the key in Agora revokes the old pairing; disconnect and reconnect the add-in.
- **Custom add-in option missing:** your mailbox may not support Outlook add-ins, or your organisation may restrict sideloading. The XML manifest may need to be deployed by your Microsoft 365 administrator.
- **Compose draft:** Agora captures received and sent message read views; draft compose mode is intentionally unsupported.
- **Duplicate:** an already-saved message is reused. Repeated commitment titles from the same source are reused; different titles create new promises. The preferred deduplication key is the Internet message ID plus your mailbox address; the Outlook item ID is the fallback and can change if a message moves.

The receiver binds only to IPv4 loopback, accepts the expected localhost Host/Origin values, limits requests to 1 MB, and requires the profile's pairing token for both connection checks and capture. Capture also requires the destination profile ID. A bootstrap endpoint exposes only the selected profile's ID and name; it exposes no records or keys. The receiver serves only explicit add-in asset routes and uses no CORS wildcard. No mailbox data is saved just by opening the task pane. Local HTTPS is configured once per Mac and shared across profiles.

Reference: [Microsoft's current Outlook add-in sideloading instructions](https://learn.microsoft.com/en-us/office/dev/add-ins/outlook/sideload-outlook-add-ins-for-testing).
