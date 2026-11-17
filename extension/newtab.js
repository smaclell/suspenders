import { phaseAt, greetingFor, parseTime } from "./lib/schedule.js";
import { QUOTES, pickQuote } from "./lib/quotes.js";
import { getSettings, getLocal, setLocal } from "./lib/store.js";
import { fetchSnippet, fetchStatus } from "./lib/helper.js";

const $ = (id) => document.getElementById(id);
let settings;

function skyFor(date, phase) {
  if (phase === "night") return "night";
  if (phase === "evening") return "evening";
  const h = date.getHours();
  if (h < 5) return "night";
  if (h < 10) return "dawn";
  if (h < 17) return "day";
  return "dusk";
}

function formatClock(date) {
  return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M$/i, "");
}

function formatDuration(mins) {
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  return h ? `${h}h ${m}m` : `${m}m`;
}

function minutesUntil(date, hhmm) {
  const t = date.getHours() * 60 + date.getMinutes();
  let diff = parseTime(hhmm) - t;
  if (diff < 0) diff += 1440;
  return diff;
}

function tick() {
  const now = new Date();
  const phase = phaseAt(now, settings);
  $("clock").textContent = formatClock(now);
  const name = settings.name?.trim();
  $("greeting").textContent = name ? `${greetingFor(now)}, ${name}.` : `${greetingFor(now)}.`;
  document.body.dataset.sky = skyFor(now, phase);
  document.body.dataset.phase = phase;
  renderStatus(now, phase);
}

let helperStatus = null;

function renderStatus(now, phase) {
  const el = $("status");
  let text = "";
  if (phase === "evening") {
    text = `YouTube calm mode · sign-off in ${formatDuration(minutesUntil(now, settings.nightStart))}`;
  } else if (phase === "night") {
    const active = helperStatus?.activeMinutesTonight;
    text = active != null ? `Time to rest · ${formatDuration(active)} on the laptop tonight` : "Time to rest · YouTube is asleep";
  }
  el.hidden = !text;
  if (text) {
    el.replaceChildren(Object.assign(document.createElement("span"), { className: "dot" }), text);
  }
}

// ---------- intention ----------
function todayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

async function setupIntention() {
  const form = $("intention");
  const input = $("intention-input");
  const text = $("intention-text");
  const label = $("intention-label");
  const phase = phaseAt(new Date(), settings);
  label.textContent = phase === "night" ? "How do I want tomorrow to begin?" : "Who do I want to be today?";

  const show = (value) => {
    const has = Boolean(value);
    text.textContent = value || "";
    text.hidden = !has;
    input.hidden = has;
    label.hidden = has && phase !== "night";
  };

  const saved = await getLocal("intention", null);
  show(saved?.date === todayKey() ? saved.text : "");

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const value = input.value.trim();
    await setLocal("intention", { date: todayKey(), text: value });
    show(value);
  });
  text.addEventListener("click", () => {
    input.value = text.textContent;
    show("");
    input.focus();
  });
}

// ---------- card ----------
function quotePool() {
  const custom = (settings.customQuotes || []).map((q) => ({ theme: "custom", ...q }));
  return settings.showBuiltInQuotes ? [...custom, ...QUOTES] : custom.length ? custom : QUOTES;
}

async function nextItem() {
  const phase = phaseAt(new Date(), settings);
  if (Math.random() < settings.noteWeight) {
    const snippet = await fetchSnippet(settings.helperPort);
    if (snippet?.text) return snippet;
  }
  const q = pickQuote(quotePool(), phase);
  return { kind: "quote", text: q.text, author: q.author };
}

function renderCard(item) {
  const card = $("card");
  const caption = $("card-caption");
  card.classList.toggle("quote", item.kind === "quote");
  $("card-text").textContent = item.kind === "quote" ? `“${item.text}”` : item.text;

  if (item.kind === "quote" && item.source !== "vault") {
    $("card-kicker").textContent = item.author ? "" : "Reminder";
    caption.textContent = item.author ? `— ${item.author}` : "";
  } else {
    $("card-kicker").textContent = item.kind === "quote" ? "From your quotes" : "From your notes";
    const parts = [item.title, item.heading].filter(Boolean).join(" › ");
    caption.textContent = item.author ? `— ${item.author}` : parts;
    if (item.obsidianURL) {
      const a = document.createElement("a");
      a.href = item.obsidianURL;
      a.textContent = "Open in Obsidian ↗";
      caption.append(a);
    }
  }
}

let swapping = false;
async function showNext() {
  if (swapping) return;
  swapping = true;
  const card = $("card");
  card.classList.add("swap");
  const [item] = await Promise.all([nextItem(), new Promise((r) => setTimeout(r, 250))]);
  renderCard(item);
  card.classList.remove("swap");
  swapping = false;
}

// ---------- boot ----------
async function main() {
  settings = await getSettings();
  tick();
  setInterval(tick, 1000 * 5);
  setupIntention();
  renderCard(await nextItem());

  fetchStatus(settings.helperPort).then((s) => {
    helperStatus = s;
    tick();
  });

  $("next").addEventListener("click", showNext);
  document.addEventListener("keydown", (e) => {
    if (e.target instanceof HTMLInputElement) return;
    if (e.key === " " || e.key === "ArrowRight") {
      e.preventDefault();
      showNext();
    }
  });
}

main();
