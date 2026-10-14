// Exercise the shipped task pane script with Office events and profile changes.
// No mailbox, private pairing keys, browser account or external dependencies are used.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const elements = new Map();
function element(id) {
  if (!elements.has(id)) elements.set(id, { textContent: "", value: "", className: "", hidden: false, disabled: false, children: [], handlers: {}, addEventListener(name, handler) { this.handlers[name] = handler; }, replaceChildren() { this.children = []; }, append(child) { this.children.push(child); } });
  return elements.get(id);
}
const work = { id: "default", name: "Work" }, university = { id: "university-test", name: "University" };
const keys = { default: "a".repeat(64), "university-test": "b".repeat(64) };
const storage = new Map([["agora-pairing", keys.default]]);
const captures = [];
const intervals = [];
let selected = work, startup;
const Office = {
  HostType: { Outlook: "Outlook" }, CoercionType: { Text: "text" }, AsyncResultStatus: { Succeeded: "ok" }, EventType: { ItemChanged: "changed" },
  onReady(callback) { startup = callback({ host: "Outlook" }); },
  context: { mailbox: { userProfile: { emailAddress: "me@example.com" }, addHandlerAsync() {}, item: { itemId: "email-1", subject: "Test email", internetMessageId: "message-1", dateTimeCreated: new Date(), from: { emailAddress: "person@example.com", displayName: "Test person" }, body: { getAsync(type, callback) { callback({ status: "ok", value: "An email body" }); } } } } }
};
async function fetch(path, options = {}) {
  let status = 200, result;
  if (path === "/profile") result = selected;
  else if (options.headers.Authorization !== `Bearer ${keys[selected.id]}`) { status = 401; result = { error: "Pair the selected profile." }; }
  else if (path === "/api/ping") result = { connected: true, profile: selected };
  else if (path === "/api/capture") {
    if (options.headers["X-Agora-Profile"] !== selected.id) { status = 409; result = { error: "Destination profile changed." }; }
    else { captures.push({ profile: selected.id, body: JSON.parse(options.body) }); result = { alreadySaved: false, commitmentIds: [] }; }
  } else throw new Error("Unexpected URL: " + path);
  return { status, ok: status === 200, json: async () => result, text: async () => JSON.stringify(result) };
}
vm.runInNewContext(fs.readFileSync(new URL("../Sources/AgoraMac/Resources/Outlook/taskpane.js", import.meta.url), "utf8"), {
  document: { hidden: false, getElementById: element, createElement: () => ({}) },
  localStorage: { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
  Office, fetch, Date, AbortSignal, setInterval: callback => intervals.push(callback)
});
await startup;
assert.equal(element("profile-name").textContent, "Saving to Work");
assert.equal(element("capture").hidden, false);
await element("save").handlers.click();
assert.equal(captures[0].profile, work.id);

element("promises").children.push({ unsavedWorkDraft: true });
selected = university;
intervals[0]();
await new Promise(resolve => setImmediate(resolve));
assert.equal(element("profile-name").textContent, "Saving to University");
assert.equal(element("pairing").hidden, false);
assert.equal(element("promises").children.length, 0);
element("key").value = keys[university.id];
await element("pair").handlers.click();
await element("save").handlers.click();
assert.equal(captures[1].profile, university.id);

// Switch in the native app immediately before saving, before the polling timer fires.
selected = work;
await element("save").handlers.click();
assert.equal(captures.length, 2, "A stale pairing must not save into the other profile");
assert.equal(element("pairing").hidden, false);
assert.equal(element("save").disabled, true);
intervals[0]();
await new Promise(resolve => setImmediate(resolve));
assert.equal(element("key").value, keys[work.id], "Previously paired profiles can reuse their own saved key");
await element("pair").handlers.click();
await element("save").handlers.click();
assert.equal(captures[2].profile, work.id);
console.log("Outlook pane smoke passed: destination label, legacy pairing, per-profile keys, cleared drafts on switch, stale-save rejection and reconnect.");
