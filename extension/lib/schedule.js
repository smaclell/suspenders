// Pure schedule logic — no chrome.* APIs so it can be unit tested in Node.

export const DEFAULT_SETTINGS = Object.freeze({
  name: "",
  eveningStart: "20:30", // YouTube friction begins
  nightStart: "22:00", // YouTube blocked, sign-off nudges
  morningStart: "05:00", // everything back to normal
  gateSeconds: 10,
  grayscaleFullMinutes: 30, // minutes of watching until fully grey
  minReasonWords: 20,
  unlockWaitMinutes: 5,
  unlockDurationMinutes: 15,
  helperPort: 47615,
  customQuotes: [], // [{ text, author }]
  showBuiltInQuotes: true,
  noteWeight: 0.6, // chance of showing a note passage when the helper is available
  interruptEvery: 3, // reflect on every Nth video in a row (0 = off)
  streakGapMinutes: 30, // a break this long starts a new streak
  reflectionMinWords: 3,
  dimAlways: true, // dim Shorts + recommendations at any time of day
});

/** "HH:MM" → minutes after midnight. */
export function parseTime(hhmm) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm).trim());
  if (!m) throw new Error(`Invalid time: ${hhmm}`);
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) throw new Error(`Invalid time: ${hhmm}`);
  return h * 60 + min;
}

function minutesOf(date) {
  return date.getHours() * 60 + date.getMinutes();
}

/** Is `t` inside [start, end) on a 24h clock that may wrap past midnight? */
function inWindow(t, start, end) {
  if (start === end) return false;
  return start < end ? t >= start && t < end : t >= start || t < end;
}

/**
 * Returns "day" | "evening" | "night".
 * evening: eveningStart → nightStart, night: nightStart → morningStart.
 */
export function phaseAt(date, settings = DEFAULT_SETTINGS) {
  const t = minutesOf(date);
  const evening = parseTime(settings.eveningStart);
  const night = parseTime(settings.nightStart);
  const morning = parseTime(settings.morningStart);
  if (inWindow(t, night, morning)) return "night";
  if (inWindow(t, evening, night)) return "evening";
  return "day";
}

/**
 * A stable key for "tonight" so counters reset each morning rather than at
 * midnight. Times before morningStart belong to the previous day.
 */
export function nightKey(date, settings = DEFAULT_SETTINGS) {
  const d = new Date(date);
  if (minutesOf(d) < parseTime(settings.morningStart)) d.setDate(d.getDate() - 1);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/** Minutes elapsed since nightStart (0 if not night). */
export function minutesPastNight(date, settings = DEFAULT_SETTINGS) {
  if (phaseAt(date, settings) !== "night") return 0;
  const t = minutesOf(date);
  const night = parseTime(settings.nightStart);
  return t >= night ? t - night : t + 1440 - night;
}

export function countWords(text) {
  return String(text).trim().split(/\s+/).filter(Boolean).length;
}

export function greetingFor(date) {
  const h = date.getHours();
  if (h < 5) return "Rest well";
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  if (h < 22) return "Good evening";
  return "Time to rest";
}

/** CSS grayscale amount (0–1) for minutes watched this evening. */
export function grayscaleFor(minutesWatched, settings = DEFAULT_SETTINGS) {
  const full = Math.max(1, settings.grayscaleFullMinutes);
  return Math.min(1, Math.max(0, minutesWatched / full));
}

export function withDefaults(stored) {
  return { ...DEFAULT_SETTINGS, ...(stored || {}) };
}
