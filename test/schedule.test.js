import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_SETTINGS,
  parseTime,
  phaseAt,
  nightKey,
  minutesPastNight,
  countWords,
  grayscaleFor,
} from "../extension/lib/schedule.js";
import { pickQuote, textToQuotes, QUOTES } from "../extension/lib/quotes.js";

const at = (h, m = 0, day = 16) => new Date(2026, 10, day, h, m);

test("parseTime", () => {
  assert.equal(parseTime("20:30"), 1230);
  assert.equal(parseTime("5:00"), 300);
  assert.throws(() => parseTime("25:00"));
  assert.throws(() => parseTime("nope"));
});

test("phaseAt with defaults", () => {
  assert.equal(phaseAt(at(12)), "day");
  assert.equal(phaseAt(at(20, 29)), "day");
  assert.equal(phaseAt(at(20, 30)), "evening");
  assert.equal(phaseAt(at(21, 59)), "evening");
  assert.equal(phaseAt(at(22, 0)), "night");
  assert.equal(phaseAt(at(2, 0)), "night");
  assert.equal(phaseAt(at(4, 59)), "night");
  assert.equal(phaseAt(at(5, 0)), "day");
});

test("phaseAt when night starts after midnight", () => {
  const s = { ...DEFAULT_SETTINGS, eveningStart: "23:00", nightStart: "00:30", morningStart: "06:00" };
  assert.equal(phaseAt(at(22, 59), s), "day");
  assert.equal(phaseAt(at(23, 30), s), "evening");
  assert.equal(phaseAt(at(0, 15), s), "evening");
  assert.equal(phaseAt(at(0, 30), s), "night");
  assert.equal(phaseAt(at(6, 0), s), "day");
});

test("nightKey groups after-midnight with the previous evening", () => {
  assert.equal(nightKey(at(23, 0, 16)), "2026-11-16");
  assert.equal(nightKey(at(1, 0, 17)), "2026-11-16");
  assert.equal(nightKey(at(5, 0, 17)), "2026-11-17");
});

test("minutesPastNight", () => {
  assert.equal(minutesPastNight(at(21, 0)), 0);
  assert.equal(minutesPastNight(at(22, 45)), 45);
  assert.equal(minutesPastNight(at(0, 30, 17)), 150);
});

test("countWords", () => {
  assert.equal(countWords("  one two\nthree  "), 3);
  assert.equal(countWords(""), 0);
});

test("grayscaleFor clamps between 0 and 1", () => {
  assert.equal(grayscaleFor(0), 0);
  assert.equal(grayscaleFor(15), 0.5);
  assert.equal(grayscaleFor(90), 1);
});

test("pickQuote favours rest at night", () => {
  let rest = 0;
  let seed = 1;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 2000; i++) if (pickQuote(QUOTES, "night", rand).theme === "rest") rest++;
  assert.ok(rest / 2000 > 0.6, `rest share was ${rest / 2000}`);
});

test("textToQuotes parses authors", () => {
  assert.deepEqual(textToQuotes("Be here. — Someone\nJust a line\n\n"), [
    { text: "Be here.", author: "Someone" },
    { text: "Just a line" },
  ]);
});
