// Service worker: the single source of truth for "what should YouTube do right now?"

import { phaseAt, minutesPastNight } from "./lib/schedule.js";
import {
  getSettings,
  getOverrideUntil,
  setLocal,
  getLocal,
  addReason,
  addReflection,
  getWatchSeconds,
  addWatchSeconds,
} from "./lib/store.js";
import { activeSession, recordVideo, touch, resolveReflection } from "./lib/streak.js";
import { postReason } from "./lib/helper.js";

async function youtubeState() {
  const now = new Date();
  const settings = await getSettings();
  const phase = phaseAt(now, settings);
  const overrideUntil = await getOverrideUntil();
  const overridden = phase === "night" && overrideUntil > now.getTime();
  const watchSeconds = await getWatchSeconds(now, settings);
  const session = activeSession(await getLocal("streak", null), now.getTime(), settings.streakGapMinutes);
  return {
    phase,
    blocked: phase === "night" && !overridden,
    overridden,
    overrideUntil,
    calm: phase !== "day", // hide recommendations + grayscale
    watchSeconds,
    minutesPastNight: minutesPastNight(now, settings),
    streak: { count: session.ids.length, pending: session.pending },
    settings,
  };
}

async function startUnlock(reason) {
  const pending = { reason, startedAt: Date.now() };
  await setLocal("pendingUnlock", pending);
  return pending;
}

async function completeUnlock() {
  const settings = await getSettings();
  const pending = await getLocal("pendingUnlock", null);
  if (!pending) return { ok: false, error: "No reason written yet." };
  const waitMs = settings.unlockWaitMinutes * 60_000;
  if (Date.now() - pending.startedAt < waitMs) return { ok: false, error: "Still waiting." };

  const until = Date.now() + settings.unlockDurationMinutes * 60_000;
  const entry = {
    at: new Date().toISOString(),
    reason: pending.reason,
    site: "youtube.com",
    unlockMinutes: settings.unlockDurationMinutes,
  };
  await addReason(entry);
  await setLocal("overrideUntil", until);
  await chrome.storage.local.remove("pendingUnlock");
  postReason(settings.helperPort, entry); // fire and forget
  return { ok: true, until };
}

const handlers = {
  state: () => youtubeState(),
  watched: async ({ seconds }) => {
    const now = new Date();
    const settings = await getSettings();
    await setLocal("streak", touch(await getLocal("streak", null), now.getTime(), settings.streakGapMinutes));
    // Only evening/night watching counts towards the grayscale fade.
    if (phaseAt(now, settings) === "day") return { watchSeconds: await getWatchSeconds(now, settings) };
    return { watchSeconds: await addWatchSeconds(seconds, now, settings) };
  },
  videoStarted: async ({ id }) => {
    const settings = await getSettings();
    const session = recordVideo(await getLocal("streak", null), String(id), Date.now(), {
      every: settings.interruptEvery,
      gapMinutes: settings.streakGapMinutes,
    });
    await setLocal("streak", session);
    return { count: session.ids.length, pending: session.pending };
  },
  reflect: async ({ answer, question, count, title }) => {
    const settings = await getSettings();
    await setLocal("streak", resolveReflection(await getLocal("streak", null)));
    const entry = { at: new Date().toISOString(), kind: "Reflection", question, reason: answer, count, title, site: "youtube.com" };
    await addReflection(entry);
    postReason(settings.helperPort, entry);
    return { ok: true };
  },
  startUnlock: ({ reason }) => startUnlock(reason),
  cancelUnlock: () => chrome.storage.local.remove("pendingUnlock").then(() => ({ ok: true })),
  completeUnlock: () => completeUnlock(),
};

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const handler = handlers[msg?.type];
  if (!handler) return false;
  Promise.resolve(handler(msg, sender))
    .then(sendResponse)
    .catch((err) => sendResponse({ ok: false, error: String(err) }));
  return true; // async response
});

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === "install") chrome.runtime.openOptionsPage();
});
