// Thin wrappers over chrome.storage. Settings sync across Chrome profiles;
// everything else (reasons, watch time, overrides) stays on this device.

import { withDefaults, nightKey } from "./schedule.js";

export async function getSettings() {
  const { settings } = await chrome.storage.sync.get("settings");
  return withDefaults(settings);
}

export async function saveSettings(patch) {
  const current = await getSettings();
  const settings = { ...current, ...patch };
  await chrome.storage.sync.set({ settings });
  return settings;
}

export async function getLocal(key, fallback) {
  const result = await chrome.storage.local.get(key);
  return result[key] ?? fallback;
}

export function setLocal(key, value) {
  return chrome.storage.local.set({ [key]: value });
}

export async function getOverrideUntil() {
  return getLocal("overrideUntil", 0);
}

export async function getReasons() {
  return getLocal("reasons", []);
}

export async function addReason(entry) {
  const reasons = await getReasons();
  reasons.push(entry);
  await setLocal("reasons", reasons);
  return reasons;
}

export async function getWatchSeconds(date, settings) {
  const watch = await getLocal("watch", {});
  return watch[nightKey(date, settings)] ?? 0;
}

export async function addWatchSeconds(seconds, date, settings) {
  const watch = await getLocal("watch", {});
  const key = nightKey(date, settings);
  watch[key] = (watch[key] ?? 0) + seconds;
  // keep two weeks of history
  const keys = Object.keys(watch).sort();
  for (const k of keys.slice(0, Math.max(0, keys.length - 14))) delete watch[k];
  await setLocal("watch", watch);
  return watch[key];
}

export async function getReflections() {
  return getLocal("reflections", []);
}

export async function addReflection(entry) {
  const list = await getReflections();
  list.push(entry);
  await setLocal("reflections", list.slice(-500));
}
