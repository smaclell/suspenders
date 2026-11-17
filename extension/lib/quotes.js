// Built-in quotes grouped by value. Entries without an author are identity
// statements — short reminders written in the first person.

export const QUOTES = [
  // Rest & presence
  { theme: "rest", text: "Almost everything will work again if you unplug it for a few minutes, including you.", author: "Anne Lamott" },
  { theme: "rest", text: "How we spend our days is, of course, how we spend our lives.", author: "Annie Dillard" },
  { theme: "rest", text: "Rest is not idleness, and to lie sometimes on the grass under trees on a summer's day, listening to the murmur of the water, or watching the clouds float across the sky, is by no means a waste of time.", author: "John Lubbock" },
  { theme: "rest", text: "Wherever you are, be all there.", author: "Jim Elliot" },
  { theme: "rest", text: "I am someone who protects my sleep. Tomorrow's me is counting on tonight's me." },
  { theme: "rest", text: "The screen will still be here tomorrow. This evening won't." },
  { theme: "rest", text: "I give the people I love my full attention, not my leftover attention." },

  // Craft & focus
  { theme: "craft", text: "Every action you take is a vote for the type of person you wish to become.", author: "James Clear" },
  { theme: "craft", text: "You do not rise to the level of your goals. You fall to the level of your systems.", author: "James Clear" },
  { theme: "craft", text: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.", author: "Will Durant" },
  { theme: "craft", text: "Clarity about what matters provides clarity about what does not.", author: "Cal Newport" },
  { theme: "craft", text: "Simplicity is prerequisite for reliability.", author: "Edsger W. Dijkstra" },
  { theme: "craft", text: "Do the thing and you will have the power.", author: "Ralph Waldo Emerson" },
  { theme: "craft", text: "I make things. Consuming is fine; creating is who I am." },

  // Growth & courage
  { theme: "growth", text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius" },
  { theme: "growth", text: "The impediment to action advances action. What stands in the way becomes the way.", author: "Marcus Aurelius" },
  { theme: "growth", text: "We suffer more often in imagination than in reality.", author: "Seneca" },
  { theme: "growth", text: "It is not that we have a short time to live, but that we waste a lot of it.", author: "Seneca" },
  { theme: "growth", text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus" },
  { theme: "growth", text: "Courage is the most important of all the virtues, because without courage you can't practice any other virtue consistently.", author: "Maya Angelou" },
  { theme: "growth", text: "Discipline equals freedom.", author: "Jocko Willink" },
  { theme: "growth", text: "Small, boring, repeated. That's how I become who I want to be." },
];

/** Evening and night lean towards rest; the day leans towards craft and growth. */
export function themeWeights(phase) {
  if (phase === "night") return { rest: 6, craft: 1, growth: 1 };
  if (phase === "evening") return { rest: 3, craft: 1, growth: 1 };
  return { rest: 1, craft: 2, growth: 2 };
}

export function pickQuote(pool, phase, rand = Math.random) {
  if (!pool.length) return null;
  const weights = themeWeights(phase);
  const w = pool.map((q) => weights[q.theme] ?? 1);
  const total = w.reduce((a, b) => a + b, 0);
  let r = rand() * total;
  for (let i = 0; i < pool.length; i++) {
    r -= w[i];
    if (r < 0) return pool[i];
  }
  return pool[pool.length - 1];
}

/** Parse "text — Author" lines from the settings textarea. */
export function textToQuotes(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const m = /^(.*?)\s+[—–-]{1,2}\s+([^—–]+)$/.exec(line);
      return m ? { text: m[1].replace(/^["“]|["”]$/g, ""), author: m[2].trim() } : { text: line };
    });
}
