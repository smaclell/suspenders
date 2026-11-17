import { countWords } from "./lib/schedule.js";
import { QUOTES, pickQuote } from "./lib/quotes.js";
import { getSettings, getLocal, getReasons } from "./lib/store.js";

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const from = safeYouTubeURL(params.get("from"));
let settings;
let waitTimer;

function safeYouTubeURL(raw) {
  try {
    const u = new URL(raw);
    if (/(^|\.)youtube\.com$/.test(u.hostname) && u.protocol === "https:") return u.href;
  } catch {}
  return "https://www.youtube.com/";
}

const send = (msg) => chrome.runtime.sendMessage(msg);
const closeTab = async () => {
  const tab = await chrome.tabs.getCurrent();
  if (tab?.id != null) chrome.tabs.remove(tab.id);
  else window.close();
};

function fmtTime(date) {
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function show(step) {
  $("actions").hidden = step !== "start";
  $("step-reason").hidden = step !== "reason";
  $("step-wait").hidden = step !== "wait";
  if (step === "reason") $("reason").focus();
}

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

async function main() {
  settings = await getSettings();
  const now = new Date();
  $("clock").textContent = fmtTime(now);
  $("sub").textContent = `It'll be back at ${settings.morningStart.replace(/^0/, "")}. So will you, a little more rested.`;
  $("min-words").textContent = settings.minReasonWords;

  const q = pickQuote(QUOTES.filter((x) => x.theme === "rest"), "night");
  const quote = $("quote");
  quote.textContent = `“${q.text}”`;
  if (q.author) quote.append(Object.assign(document.createElement("cite"), { textContent: `— ${q.author}` }));

  renderHistory();

  // Not actually night any more (or already unlocked)? Go back.
  const state = await send({ type: "state" });
  if (state && !state.blocked) {
    location.replace(from);
    return;
  }

  const pending = await getLocal("pendingUnlock", null);
  if (pending) startWaitUI(pending);
  else show("start");

  $("close").addEventListener("click", () => closeTab());
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
    closeTab();
  });
  $("unlock").addEventListener("click", async () => {
    const res = await send({ type: "completeUnlock" });
    if (res?.ok) location.replace(from);
    else $("wait-hint").textContent = res?.error || "Something went wrong.";
  });
  updateWordCount();
}

main();
