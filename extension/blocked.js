import { countWords } from "./lib/schedule.js";
import { QUOTES, pickQuote } from "./lib/quotes.js";
import { getSettings, getLocal, getReasons } from "./lib/store.js";

// This page doubles as a "parking spot": the YouTube tab you were on stays open
// here (title + link + timestamp) and returns to the video in the morning.
// mode=night  → arrived because YouTube is blocked
// mode=saved  → you chose "Save it for later" from the evening gate (or here)

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const from = safeYouTubeURL(params.get("from"));
const savedTitle = (params.get("title") || "").slice(0, 300);
let mode = params.get("mode") === "saved" ? "saved" : "night";
let settings;
let waitTimer;
let phase = "night";

function safeYouTubeURL(raw) {
  try {
    const u = new URL(raw);
    if (/(^|\.)youtube\.com$/.test(u.hostname) && u.protocol === "https:") return u.href;
  } catch {}
  return "https://www.youtube.com/";
}

const send = (msg) => chrome.runtime.sendMessage(msg);

function fmtTime(date) {
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function morningLabel() {
  return settings.morningStart.replace(/^0/, "");
}

function show(step) {
  $("actions").hidden = step !== "start";
  $("step-reason").hidden = step !== "reason";
  $("step-wait").hidden = step !== "wait";
  if (step === "reason") $("reason").focus();
}

// ---------- saved card ----------

function isHomePage() {
  const u = new URL(from);
  return u.pathname === "/" && !u.search;
}

function prettyURL() {
  const u = new URL(from);
  return u.hostname.replace(/^www\./, "") + u.pathname + (u.searchParams.get("v") ? `?v=${u.searchParams.get("v")}` : "");
}

function renderSavedCard() {
  if (isHomePage()) return; // nothing worth keeping
  $("saved").hidden = false;
  const link = $("saved-link");
  link.textContent = savedTitle || prettyURL();
  link.href = from;
  link.title = from;
  const t = parseInt(new URL(from).searchParams.get("t") || "", 10);
  const resume = t > 0 ? ` · resumes at ${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}` : "";
  $("saved-url").textContent = prettyURL() + resume;
  document.title = `💤 ${savedTitle || "Saved for later"}`;
}

/** Switch the page to its calm "saved" state. */
function enterSaved() {
  mode = "saved";
  document.body.classList.add("is-saved");
  history.replaceState(null, "", "?" + new URLSearchParams({ ...Object.fromEntries(params), mode: "saved" }));
  $("headline").textContent = "Saved for later.";
  $("sub").textContent =
    phase === "night"
      ? `It'll be right here in the morning. Go rest.`
      : `Enjoy your evening. It'll be right here when you come back.`;
  $("saved-kicker").textContent = phase === "night" ? "Waiting for you in the morning" : "Saved for later";
  $("close").hidden = true;
  $("need").hidden = phase !== "night";
  $("open-now").hidden = phase === "night";
  show("start");
}

// ---------- returning to the video ----------

/** Daytime, or (for a blocked tab) an active unlock → go back to the video. */
function shouldReturn(state) {
  if (!state) return false;
  if (state.phase === "day") return true;
  return mode === "night" && !state.blocked;
}

async function maybeReturn() {
  if (document.visibilityState !== "visible") return; // only when you're actually looking
  const state = await send({ type: "state" });
  if (state) phase = state.phase;
  if (shouldReturn(state)) location.replace(from);
}

// ---------- unlock flow ----------

function updateWordCount() {
  const n = countWords($("reason").value);
  const ok = n >= settings.minReasonWords;
  $("word-count").textContent = `${n} / ${settings.minReasonWords} words`;
  $("word-count").classList.toggle("ok", ok);
  $("submit-reason").disabled = !ok;
}

function startWaitUI(pending) {
  show("wait");
  $("your-reason").textContent = `“${pending.reason}”`;
  $("unlock").textContent = `Unlock for ${settings.unlockDurationMinutes} minutes`;
  const total = settings.unlockWaitMinutes * 60_000;
  const circumference = 339.292;
  clearInterval(waitTimer);
  const render = () => {
    const left = Math.max(0, total - (Date.now() - pending.startedAt));
    const s = Math.ceil(left / 1000);
    $("remaining").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    $("progress").style.strokeDashoffset = String(circumference * (left / total));
    if (left <= 0) {
      clearInterval(waitTimer);
      $("unlock").disabled = false;
      $("wait-hint").textContent = "Okay. Go do the thing you came for — then rest.";
    }
  };
  render();
  waitTimer = setInterval(render, 1000);
}

async function renderHistory() {
  const reasons = await getReasons();
  const weekAgo = Date.now() - 7 * 86_400_000;
  const recent = reasons.filter((r) => Date.parse(r.at) > weekAgo).length;
  $("history").textContent =
    recent === 0 ? "No late-night unlocks this week." : `${recent} late-night unlock${recent === 1 ? "" : "s"} this week.`;
}

// ---------- boot ----------

async function main() {
  settings = await getSettings();
  $("clock").textContent = fmtTime(new Date());
  $("sub").textContent = `It'll be back at ${morningLabel()}. So will you, a little more rested.`;
  $("min-words").textContent = settings.minReasonWords;

  const q = pickQuote(QUOTES.filter((x) => x.theme === "rest"), "night");
  const quote = $("quote");
  quote.textContent = `“${q.text}”`;
  if (q.author) quote.append(Object.assign(document.createElement("cite"), { textContent: `— ${q.author}` }));

  renderHistory();
  renderSavedCard();

  const state = await send({ type: "state" });
  if (state) phase = state.phase;
  if (shouldReturn(state)) {
    location.replace(from);
    return;
  }

  const pending = await getLocal("pendingUnlock", null);
  if (mode === "saved") enterSaved();
  else if (pending) startWaitUI(pending);
  else show("start");

  $("close").addEventListener("click", enterSaved);
  $("open-now").addEventListener("click", () => location.replace(from));
  $("need").addEventListener("click", () => show("reason"));
  $("cancel-reason").addEventListener("click", () => show("start"));
  $("reason").addEventListener("input", updateWordCount);
  $("submit-reason").addEventListener("click", async () => {
    const reason = $("reason").value.trim();
    if (countWords(reason) < settings.minReasonWords) return;
    const p = await send({ type: "startUnlock", reason });
    startWaitUI(p);
  });
  $("cancel-wait").addEventListener("click", async () => {
    await send({ type: "cancelUnlock" });
    clearInterval(waitTimer);
    enterSaved();
  });
  $("unlock").addEventListener("click", async () => {
    const res = await send({ type: "completeUnlock" });
    if (res?.ok) location.replace(from);
    else $("wait-hint").textContent = res?.error || "Something went wrong.";
  });
  $("copy-link").addEventListener("click", async () => {
    await navigator.clipboard.writeText(from);
    $("copy-link").textContent = "Copied ✓";
    setTimeout(() => ($("copy-link").textContent = "Copy link"), 1500);
  });
  // Link inside the card: at night it would just bounce back here, so treat it as copy.
  $("saved-link").addEventListener("click", (e) => {
    if (phase === "night") {
      e.preventDefault();
      $("copy-link").click();
    }
  });
  updateWordCount();

  // Come back to the video once it's daytime and you look at the tab again.
  document.addEventListener("visibilitychange", maybeReturn);
  setInterval(maybeReturn, 60_000);
}

main();
