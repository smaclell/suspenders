// Pure "videos in a row" logic so it can be unit tested.
// A streak is a run of distinct videos with no gap longer than `gapMinutes`.

export function newSession(now) {
  return { ids: [], lastActive: now, pending: false };
}

function isAlive(session, now, gapMinutes) {
  return Boolean(session) && now - session.lastActive <= gapMinutes * 60_000;
}

/** Current session, or a fresh one if the old one went quiet. */
export function activeSession(session, now, gapMinutes) {
  return isAlive(session, now, gapMinutes) ? session : newSession(now);
}

/**
 * Record that a video started playing.
 * Every `every`th distinct video sets `pending` (a reflection is due).
 */
export function recordVideo(session, id, now, { every, gapMinutes }) {
  const s = { ...activeSession(session, now, gapMinutes) };
  s.ids = [...s.ids];
  s.lastActive = now;
  if (!s.ids.includes(id)) {
    s.ids.push(id);
    if (s.ids.length > 200) s.ids = s.ids.slice(-200);
    if (every > 0 && s.ids.length % every === 0) s.pending = true;
  }
  return s;
}

/** Keep the streak alive while something is playing. */
export function touch(session, now, gapMinutes) {
  if (!isAlive(session, now, gapMinutes)) return session;
  return { ...session, lastActive: now };
}

export function resolveReflection(session) {
  return session ? { ...session, pending: false } : session;
}

export const REFLECTION_QUESTIONS = [
  "What are you learning right now?",
  "Who are you becoming with this?",
  "Is this the person you want to be today?",
  "What would you rather do with the next hour?",
  "What made you click on this one?",
  "Will you remember this video tomorrow?",
];
