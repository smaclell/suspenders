import { DEFAULT_SETTINGS, parseTime } from "./lib/schedule.js";
import { getSettings, saveSettings, getReasons } from "./lib/store.js";
import { textToQuotes } from "./lib/quotes.js";
import { fetchStatus } from "./lib/helper.js";

const form = document.getElementById("form");
const NUMBER_FIELDS = Object.keys(DEFAULT_SETTINGS).filter((k) => typeof DEFAULT_SETTINGS[k] === "number");

function quotesToText(quotes) {
  return quotes.map((q) => (q.author ? `${q.text} — ${q.author}` : q.text)).join("\n");
}

function fill(settings) {
  for (const el of form.elements) {
    if (!el.name || !(el.name in settings)) continue;
    if (el.type === "checkbox") el.checked = Boolean(settings[el.name]);
    else if (el.name === "customQuotes") el.value = quotesToText(settings.customQuotes);
    else el.value = settings[el.name];
  }
}

function read() {
  const data = Object.fromEntries(new FormData(form));
  const out = { ...data };
  for (const k of NUMBER_FIELDS) out[k] = Number(data[k]);
  out.showBuiltInQuotes = form.elements.showBuiltInQuotes.checked;
  out.customQuotes = textToQuotes(data.customQuotes || "");
  for (const k of ["eveningStart", "nightStart", "morningStart"]) parseTime(out[k]); // validate
  return out;
}

async function renderReasons() {
  const reasons = (await getReasons()).slice().reverse();
  const list = document.getElementById("reasons-list");
  const summary = document.getElementById("reasons-summary");
  list.replaceChildren();
  if (!reasons.length) {
    summary.textContent = "No late-night unlocks yet. Nice.";
    return;
  }
  const weekAgo = Date.now() - 7 * 86_400_000;
  const week = reasons.filter((r) => Date.parse(r.at) > weekAgo).length;
  summary.textContent = `${reasons.length} total · ${week} in the last 7 days`;
  for (const r of reasons) {
    const li = document.createElement("li");
    const time = document.createElement("time");
    time.dateTime = r.at;
    time.textContent = new Date(r.at).toLocaleString([], { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
    const p = document.createElement("p");
    p.textContent = r.reason;
    li.append(time, p);
    list.append(li);
  }
}

async function exportMarkdown() {
  const reasons = await getReasons();
  const md = ["# Late-night reasons", "", ...reasons.map((r) => `- **${new Date(r.at).toLocaleString()}** — ${r.reason}`)].join("\n");
  await navigator.clipboard.writeText(md);
  const btn = document.getElementById("export");
  btn.textContent = "Copied ✓";
  setTimeout(() => (btn.textContent = "Copy as Markdown"), 1500);
}

async function checkHelper(port) {
  const status = await fetchStatus(port);
  const el = document.getElementById("helper");
  const text = document.getElementById("helper-text");
  el.classList.toggle("on", Boolean(status));
  text.textContent = status
    ? `Mac helper connected · ${status.snippetCount ?? 0} passages from your notes`
    : "Mac helper not running — using built-in quotes only";
}

async function main() {
  const settings = await getSettings();
  fill(settings);
  renderReasons();
  checkHelper(settings.helperPort);

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      const saved = await saveSettings(read());
      fill(saved);
      const badge = document.getElementById("saved");
      badge.hidden = false;
      setTimeout(() => (badge.hidden = true), 1800);
      checkHelper(saved.helperPort);
    } catch (err) {
      alert(err.message);
    }
  });
  document.getElementById("export").addEventListener("click", exportMarkdown);
  chrome.storage.onChanged.addListener((changes) => {
    if (changes.reasons) renderReasons();
  });
}

main();
