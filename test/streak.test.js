import { test } from "node:test";
import assert from "node:assert/strict";
import { recordVideo, touch, resolveReflection, activeSession } from "../extension/lib/streak.js";

const opts = { every: 3, gapMinutes: 30 };
const MIN = 60_000;

test("every third distinct video is due for reflection", () => {
  let s = null;
  s = recordVideo(s, "a", 0, opts);
  s = recordVideo(s, "b", MIN, opts);
  assert.equal(s.pending, false);
  s = recordVideo(s, "c", 2 * MIN, opts);
  assert.equal(s.ids.length, 3);
  assert.equal(s.pending, true);
});

test("re-watching the same video does not count", () => {
  let s = recordVideo(null, "a", 0, opts);
  s = recordVideo(s, "a", MIN, opts);
  s = recordVideo(s, "b", 2 * MIN, opts);
  assert.equal(s.ids.length, 2);
  assert.equal(s.pending, false);
});

test("resolving clears pending and the next interrupt comes at 6", () => {
  let s = null;
  for (const [i, id] of ["a", "b", "c"].entries()) s = recordVideo(s, id, i * MIN, opts);
  s = resolveReflection(s);
  for (const [i, id] of ["d", "e"].entries()) s = recordVideo(s, id, (3 + i) * MIN, opts);
  assert.equal(s.pending, false);
  s = recordVideo(s, "f", 6 * MIN, opts);
  assert.equal(s.pending, true);
});

test("a long break starts a fresh streak", () => {
  let s = recordVideo(null, "a", 0, opts);
  s = recordVideo(s, "b", MIN, opts);
  s = recordVideo(s, "c", 40 * MIN, opts);
  assert.deepEqual(s.ids, ["c"]);
  assert.equal(s.pending, false);
});

test("watching keeps a streak alive past the gap", () => {
  let s = recordVideo(null, "a", 0, opts);
  s = touch(s, 25 * MIN, 30);
  s = touch(s, 50 * MIN, 30);
  s = recordVideo(s, "b", 70 * MIN, opts);
  assert.deepEqual(s.ids, ["a", "b"]);
});

test("interrupts can be turned off", () => {
  let s = null;
  for (const [i, id] of ["a", "b", "c", "d"].entries()) s = recordVideo(s, id, i * MIN, { every: 0, gapMinutes: 30 });
  assert.equal(s.pending, false);
});

test("activeSession expires stale sessions", () => {
  const s = recordVideo(null, "a", 0, opts);
  assert.equal(activeSession(s, 10 * MIN, 30).ids.length, 1);
  assert.equal(activeSession(s, 31 * MIN, 30).ids.length, 0);
});
