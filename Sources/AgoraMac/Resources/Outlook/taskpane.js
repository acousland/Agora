/* global Office */
"use strict";
const $ = id => document.getElementById(id);
let token = localStorage.getItem("agora-pairing") || "";
let pairings = {};
try { const saved = JSON.parse(localStorage.getItem("agora-profile-pairings") || "{}"); if (saved && typeof saved === "object" && !Array.isArray(saved)) pairings = saved; } catch { /* Start with no saved profile pairings. */ }
let destination = null;
let pairedProfile = null;
let checkingProfile = false;
let saving = false;
let emailLoadID = 0;
let email = null;
let contacts = [];
function status(text, type = "") { $("status").textContent = text; $("status").className = type; }
async function api(path, options = {}) {
  let response;
  try { response = await fetch(path, { ...options, headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}`, ...(pairedProfile ? { "X-Agora-Profile": pairedProfile.id } : {}) }, signal: AbortSignal.timeout(12000) }); }
  catch { throw new Error("Could not reach Agora. Keep the app open and check local HTTPS in Connections."); }
  const text = await response.text();
  let result; try { result = JSON.parse(text); } catch { result = null; }
  if (!response.ok) {
    if (response.status === 401 || response.status === 409) showPairing();
    throw new Error(result?.error || text || "Could not save this email.");
  }
  return result;
}
function showPairing() {
  pairedProfile = null;
  $("pairing").hidden = false; $("capture").hidden = true; $("connection").textContent = "Disconnected";
  $("save").disabled = true;
}
async function connect() {
  const result = await api("/api/ping");
  if (!destination || result.profile?.id !== destination.id) { showPairing(); throw new Error("The profile changed. Check the selected profile and connect again."); }
  pairedProfile = result.profile;
  pairings[destination.id] = token;
  localStorage.setItem("agora-profile-pairings", JSON.stringify(pairings));
  if (destination.id === "default") localStorage.removeItem("agora-pairing");
  $("pairing").hidden = true; $("capture").hidden = false; $("connection").textContent = "Connected";
  $("save").disabled = !email;
}
async function refreshDestination(initial = false) {
  if (checkingProfile || saving) return;
  checkingProfile = true;
  try {
    const response = await fetch("/profile", { cache: "no-store", signal: AbortSignal.timeout(12000) });
    if (!response.ok) throw new Error("Could not check the selected profile. Keep Agora open.");
    const current = await response.json();
    if (typeof current.id !== "string" || typeof current.name !== "string") throw new Error("Could not read the selected profile.");
    const changed = destination?.id !== current.id;
    destination = current;
    $("profile-name").textContent = `Saving to ${current.name}`;
    $("pair").textContent = `Connect ${current.name}`;
    if (changed) {
      showPairing();
      token = pairings[current.id] || (current.id === "default" ? localStorage.getItem("agora-pairing") : "") || "";
      $("key").value = token;
      await loadEmail();
      if (initial && token) { await connect(); }
      else if (!initial) { status(`Profile changed to ${current.name}. Connect this profile and review the email before saving. Unsaved commitments have been cleared.`); }
    }
  } catch (error) { status(error.message, "error"); }
  finally { checkingProfile = false; }
}
async function loadEmail() {
  const loadID = ++emailLoadID;
  email = null; $("save").disabled = true; $("promises").replaceChildren(); $("person").replaceChildren();
  const item = Office.context.mailbox.item;
  if (!item || typeof item.body?.getAsync !== "function" || !item.itemId || typeof item.subject !== "string") {
    status("Open a received or sent email to save it. Draft messages are not supported.", "error"); return;
  }
  const me = Office.context.mailbox.userProfile.emailAddress.toLowerCase();
  const candidates = [item.from, ...(Array.isArray(item.to) ? item.to : []), ...(Array.isArray(item.cc) ? item.cc : [])].filter(Boolean);
  contacts = [...new Map(candidates.filter(p => p.emailAddress && p.emailAddress.toLowerCase() !== me).map(p => [p.emailAddress.toLowerCase(), p])).values()];
  if (!contacts.length) { status("This email has no other person to link it to.", "error"); return; }
  contacts.forEach((person, index) => { const option = document.createElement("option"); option.value = String(index); option.textContent = `${person.displayName || person.emailAddress} · ${person.emailAddress}`; $("person").append(option); });
  $("subject").textContent = item.subject || "(No subject)";
  const occurred = item.dateTimeCreated instanceof Date ? item.dateTimeCreated : new Date();
  $("email-date").textContent = occurred.toLocaleString();
  try {
    const body = await new Promise((resolve, reject) => item.body.getAsync(Office.CoercionType.Text, result => result.status === Office.AsyncResultStatus.Succeeded ? resolve(result.value) : reject(new Error(result.error?.message || "Could not read the email body."))));
    if (loadID !== emailLoadID) return;
    email = { subject: item.subject || "(No subject)", body, externalId: `${me}:${item.internetMessageId || item.itemId}`, occurredAt: occurred.getTime() / 1000 };
    $("save").disabled = !pairedProfile;
  } catch (error) { status(error.message, "error"); }
}
function addPromise() {
  if ($("promises").children.length >= 20) { status("Capture at most 20 promises per email.", "error"); return; }
  const promise = document.createElement("div"); promise.className = "promise";
  promise.innerHTML = '<label>What was promised?</label><textarea class="title" maxlength="500" placeholder="e.g. Send the proposal by Friday" aria-label="Commitment title"></textarea><div class="row"><select class="direction" aria-label="Promise direction"><option value="i_owe">I promised</option><option value="they_owe">They promised</option></select><select class="priority" aria-label="Priority"><option value="normal">Normal priority</option><option value="high">High priority</option></select></div><label>Due date (optional)</label><input class="due" type="date" aria-label="Due date"><button class="remove" type="button">Remove commitment</button>';
  promise.querySelector(".remove").addEventListener("click", () => promise.remove());
  $("promises").append(promise); promise.querySelector(".title").focus();
}
$("pair").addEventListener("click", async () => {
  const enteredKey = $("key").value.trim();
  if (!/^[a-f0-9]{64}$/.test(enteredKey)) { status("Paste the 64-character key from Agora → Connections.", "error"); return; }
  const previousProfile = destination?.id;
  $("pair").disabled = true;
  try {
    await refreshDestination();
    if (previousProfile && previousProfile !== destination?.id) throw new Error("The profile changed. Review the selected profile before connecting.");
    token = enteredKey;
    await connect(); status("");
  } catch (error) { status(error.message, "error"); }
  finally { $("pair").disabled = false; }
});
$("disconnect").addEventListener("click", () => {
  if (destination) delete pairings[destination.id];
  localStorage.setItem("agora-profile-pairings", JSON.stringify(pairings)); localStorage.removeItem("agora-pairing");
  token = ""; showPairing(); $("key").value = ""; status("");
});
$("add-promise").addEventListener("click", addPromise);
$("save").addEventListener("click", async () => {
  if (!email || !pairedProfile || saving) return;
  const person = contacts[Number($("person").value)];
  if (!person) { status("Choose a person for this email.", "error"); return; }
  const commitments = [...$("promises").children].map(node => ({ title: node.querySelector(".title").value.trim(), direction: node.querySelector(".direction").value, priority: node.querySelector(".priority").value, ...(node.querySelector(".due").value ? { dueDate: node.querySelector(".due").value } : {}) }));
  if (commitments.some(p => !p.title)) { status("Give each commitment a title, or remove the empty one.", "error"); return; }
  $("save").disabled = true; saving = true;
  try {
    const result = await api("/api/capture", { method: "POST", body: JSON.stringify({ ...email, contactName: person.displayName || person.emailAddress, contactEmail: person.emailAddress, commitments }) });
    status(`${result.alreadySaved ? "Email already in your library." : "Email saved."} ${result.commitmentIds.length ? `${result.commitmentIds.length} commitment${result.commitmentIds.length === 1 ? "" : "s"} registered.` : ""} You’ll find it in Agora.`, "success");
    $("promises").replaceChildren();
  } catch (error) { status(error.message, "error"); }
  finally { saving = false; $("save").disabled = !pairedProfile; }
});
if (typeof Office !== "undefined") {
  Office.onReady(async info => {
    if (info.host !== Office.HostType.Outlook) { status("Open this add-in from an email in Outlook for Mac."); return; }
    await refreshDestination(true);
    setInterval(() => { if (!document.hidden) refreshDestination(); }, 5000);
    Office.context.mailbox.addHandlerAsync?.(Office.EventType.ItemChanged, () => { status(""); loadEmail(); });
  });
} else { status("Open this page as an Outlook add-in to capture an email."); }
