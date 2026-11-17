// Runs on every YouTube page at document_start.
// any time: dim Shorts/recs, reflect every Nth video in a row
// evening: gate + calm mode + grayscale · night: blocked (unless unlocked)
(() => {
  const root = document.documentElement;
  const TICK_SECONDS = 15;
  let state = null;
  let ui = null;

  const send = (msg) =>
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (res) => resolve(chrome.runtime.lastError ? null : res));
      } catch {
        resolve(null); // extension reloaded — leave the page alone
      }
    });

  // Hide the page until we know what to do, with a failsafe.
  root.classList.add("sus-pending");
  const failsafe = setTimeout(() => root.classList.remove("sus-pending"), 1500);

  /** The current URL, with the video's position so it resumes where you left off. */
  function resumableURL() {
    const url = new URL(location.href);
    const video = document.querySelector("video");
    if (url.pathname === "/watch" && video && video.currentTime > 5) url.searchParams.set("t", `${Math.floor(video.currentTime)}s`);
    return url.href;
  }

  function videoTitle() {
    return document.title.replace(/^\(\d+\)\s*/, "").replace(/\s*-\s*YouTube$/, "").trim();
  }

  /** Park this tab on the resting page — it keeps the link so nothing is lost. */
  function park(mode) {
    const params = new URLSearchParams({ from: resumableURL(), mode });
    const title = videoTitle();
    if (title && title !== "YouTube") params.set("title", title);
    location.replace(chrome.runtime.getURL("blocked.html") + "?" + params);
  }

  function goToBlocked() {
    park("night");
  }

  function pauseVideos() {
    document.querySelectorAll("video").forEach((v) => {
      if (!v.paused) v.pause();
    });
  }

  function isWatching() {
    if (document.visibilityState !== "visible") return false;
    return [...document.querySelectorAll("video")].some((v) => !v.paused && !v.ended && v.readyState > 2);
  }

  function applyGray() {
    const full = Math.max(1, state.settings.grayscaleFullMinutes);
    const g = Math.min(1, state.watchSeconds / 60 / full);
    root.style.setProperty("--sus-gray", g.toFixed(3));
  }

  function disableAutoplay() {
    const btn = document.querySelector('.ytp-autonav-toggle-button[aria-checked="true"]');
    if (btn) btn.click();
  }

  // ---------- UI (shadow DOM so YouTube styles can't leak in) ----------
  function ensureUI() {
    if (ui) return ui;
    const host = document.createElement("suspenders-ui");
    const shadow = host.attachShadow({ mode: "closed" });
    shadow.innerHTML = `
      <style>
        :host { all: initial; }
        * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
        .gate {
          position: fixed; inset: 0; z-index: 2147483647;
          display: grid; place-items: center;
          background: radial-gradient(120% 120% at 30% 110%, #e08a5b 0%, #352a6b 45%, #120d2b 100%);
          color: #fffaf3; text-align: center;
          animation: in .6s cubic-bezier(.22,1,.36,1) both;
        }
        .gate.out { animation: out .45s ease both; }
        .breath {
          width: 120px; height: 120px; margin: 0 auto 36px; border-radius: 50%;
          background: radial-gradient(circle, rgba(255,250,243,.55), rgba(255,250,243,.05) 70%);
          animation: breathe 8s ease-in-out infinite;
        }
        .time { font-size: 15px; letter-spacing: .14em; text-transform: uppercase; opacity: .6; }
        h1 { font-size: 44px; font-weight: 600; letter-spacing: -.02em; margin: 10px 0 8px; }
        p { font-size: 18px; opacity: .75; margin: 0 auto 36px; max-width: 460px; line-height: 1.5; }
        .actions { display: flex; gap: 12px; justify-content: center; }
        button {
          font-size: 16px; font-weight: 500; font-family: inherit; padding: 13px 22px; border-radius: 999px; cursor: pointer;
          border: 1px solid rgba(255,255,255,.25); background: rgba(255,255,255,.08); color: #fffaf3;
          transition: background .2s, opacity .2s;
        }
        button:hover:not(:disabled) { background: rgba(255,255,255,.18); }
        button.primary { background: #fffaf3; color: #1b1433; border-color: transparent; }
        button.primary:hover { background: #fff; }
        button:disabled { opacity: .45; cursor: default; }
        .pill {
          position: fixed; left: 18px; bottom: 18px; z-index: 2147483646;
          padding: 9px 14px; border-radius: 999px; font-size: 13px;
          color: #fffaf3; background: rgba(18,13,43,.78); backdrop-filter: blur(12px);
          border: 1px solid rgba(255,255,255,.14); box-shadow: 0 8px 30px rgba(0,0,0,.25);
          pointer-events: none; animation: in .6s ease both;
        }
        .count { font-size: 13px; letter-spacing: .14em; text-transform: uppercase; opacity: .55; margin-bottom: 4px; }
        .question { font-family: "New York", "Iowan Old Style", Georgia, serif; font-style: italic; font-weight: 500; }
        textarea {
          display: block; width: min(520px, 80vw); margin: 0 auto 10px; resize: none;
          font-size: 17px; line-height: 1.5; font-family: inherit; color: #fffaf3;
          background: rgba(255,255,255,.07); border: 1px solid rgba(255,255,255,.2); border-radius: 14px;
          padding: 14px 16px; outline: none;
        }
        textarea:focus { border-color: rgba(255,255,255,.45); }
        textarea::placeholder { color: rgba(255,250,243,.4); }
        .words { font-size: 13px; opacity: .5; margin-bottom: 26px; font-variant-numeric: tabular-nums; }
        .gate.reflect { background: radial-gradient(120% 120% at 70% 110%, #3e8e7e 0%, #1f3b5a 45%, #0b1426 100%); }
        @keyframes in { from { opacity: 0; } }
        @keyframes out { to { opacity: 0; } }
        @keyframes breathe { 0%,100% { transform: scale(.7); opacity: .7; } 50% { transform: scale(1.15); opacity: 1; } }
        @media (prefers-reduced-motion: reduce) { .breath { animation: none; } }
      </style>
      <div class="pill" hidden></div>`;
    root.appendChild(host);
    ui = { host, shadow, pill: shadow.querySelector(".pill") };
    return ui;
  }

  function showGate() {
    const { shadow } = ensureUI();
    const now = new Date();
    const gate = document.createElement("div");
    gate.className = "gate";
    gate.innerHTML = `
      <div>
        <div class="breath"></div>
        <div class="time"></div>
        <h1>Do I need this right now?</h1>
        <p>Take a breath. If it's worth watching, it'll still be worth it in a moment.</p>
        <div class="actions">
          <button class="primary" data-act="close">Save it for later</button>
          <button data-act="continue" disabled></button>
        </div>
      </div>`;
    gate.querySelector(".time").textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    shadow.appendChild(gate);

    const cont = gate.querySelector('[data-act="continue"]');
    let left = state.settings.gateSeconds;
    const pauser = setInterval(pauseVideos, 250);
    const countdown = () => {
      cont.textContent = left > 0 ? `Continue in ${left}…` : "Continue mindfully";
      cont.disabled = left > 0;
      left--;
    };
    countdown();
    const timer = setInterval(() => {
      countdown();
      if (left < -1) clearInterval(timer);
    }, 1000);

    gate.addEventListener("click", (e) => {
      const act = e.target?.dataset?.act;
      if (act === "close") {
        clearInterval(pauser);
        clearInterval(timer);
        park("saved");
      }
      if (act === "continue" && !cont.disabled) {
        sessionStorage.setItem("susGatePassed", String(Date.now()));
        clearInterval(pauser);
        clearInterval(timer);
        gate.classList.add("out");
        setTimeout(() => gate.remove(), 450);
      }
    });
  }

  // ---------- "videos in a row" reflection ----------
  const QUESTIONS = [
    "What are you learning right now?",
    "Who are you becoming with this?",
    "Is this the person you want to be today?",
    "What would you rather do with the next hour?",
    "What made you click on this one?",
    "Will you remember this video tomorrow?",
  ];
  let reflecting = false;

  function videoId() {
    if (location.pathname === "/watch") return new URLSearchParams(location.search).get("v");
    const m = /^\/shorts\/([\w-]+)/.exec(location.pathname);
    return m ? `short:${m[1]}` : null;
  }

  function overlayOpen() {
    return Boolean(ui?.shadow.querySelector(".gate"));
  }

  function showReflection(count) {
    if (reflecting || overlayOpen()) return;
    reflecting = true;
    const { shadow } = ensureUI();
    const question = QUESTIONS[Math.floor(Math.random() * QUESTIONS.length)];
    const min = state.settings.reflectionMinWords;
    const card = document.createElement("div");
    card.className = "gate reflect";
    card.innerHTML = `
      <div>
        <div class="count"></div>
        <h1 class="question"></h1>
        <p>This is the moment the pattern usually carries on by itself. Pause. Answer honestly.</p>
        <textarea rows="3" placeholder="A few honest words…"></textarea>
        <div class="words"></div>
        <div class="actions">
          <button class="primary" data-act="save">Save it for later</button>
          <button data-act="continue" disabled>Continue</button>
        </div>
      </div>`;
    card.querySelector(".count").textContent = `Video ${count} in a row`;
    card.querySelector(".question").textContent = question;
    shadow.appendChild(card);

    const input = card.querySelector("textarea");
    const words = card.querySelector(".words");
    const cont = card.querySelector('[data-act="continue"]');
    const pauser = setInterval(pauseVideos, 250);
    const update = () => {
      const n = input.value.trim().split(/\s+/).filter(Boolean).length;
      words.textContent = n >= min ? "Thank you." : `${n} / ${min} words`;
      cont.disabled = n < min;
    };
    update();
    input.addEventListener("input", update);
    // Keep YouTube's keyboard shortcuts (space, k, j, l…) from firing while typing.
    input.addEventListener("keydown", (e) => e.stopPropagation());
    setTimeout(() => input.focus(), 50);

    const finish = async (act) => {
      clearInterval(pauser);
      await send({ type: "reflect", answer: input.value.trim(), question, count, title: videoTitle() });
      if (act === "save") return park("saved");
      card.classList.add("out");
      setTimeout(() => card.remove(), 450);
      reflecting = false;
    };
    card.addEventListener("click", (e) => {
      const act = e.target?.dataset?.act;
      if (act === "save") finish("save");
      if (act === "continue" && !cont.disabled) finish("continue");
    });
  }

  let lastCounted = null;
  function watchForNewVideos() {
    setInterval(async () => {
      const id = videoId();
      if (!id || id === lastCounted) return;
      const video = document.querySelector("video");
      if (!video || video.paused || video.currentTime < 3) return; // only count videos that actually play
      lastCounted = id;
      const res = await send({ type: "videoStarted", id });
      if (res?.pending) showReflection(res.count);
    }, 1000);
  }

  function updatePill() {
    const { pill } = ensureUI();
    const mins = Math.round(state.watchSeconds / 60);
    let text;
    if (state.overridden) {
      const left = Math.max(0, Math.ceil((state.overrideUntil - Date.now()) / 60000));
      text = `Unlocked · ${left} min left`;
    } else {
      const [h, m] = state.settings.nightStart.split(":").map(Number);
      const at = new Date();
      at.setHours(h, m, 0, 0);
      text = `${mins} min watched tonight · YouTube rests at ${at.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`;
    }
    pill.textContent = text;
    pill.hidden = false;
  }

  // ---------- main loop ----------
  async function refresh() {
    const next = await send({ type: "state" });
    if (!next) return false;
    state = next;
    if (state.blocked) {
      goToBlocked();
      return false;
    }
    root.classList.toggle("sus-calm", state.calm);
    root.classList.toggle("sus-dim", Boolean(state.settings.dimAlways) && !state.calm);
    if (state.calm) {
      applyGray();
      disableAutoplay();
      if (document.body) updatePill();
    } else if (ui) {
      ui.pill.hidden = true;
    }
    return true;
  }

  async function start() {
    const ok = await refresh();
    clearTimeout(failsafe);
    root.classList.remove("sus-pending");
    if (!ok || !state) return;

    const onReady = () => {
      watchForNewVideos();
      // A reflection that was due but skipped (e.g. tab reloaded) still needs an answer.
      if (state.streak?.pending && videoId()) {
        lastCounted = videoId();
        showReflection(state.streak.count);
      }
      if (!state.calm) return;
      updatePill();
      const passed = Number(sessionStorage.getItem("susGatePassed") || 0);
      // Gate once per tab visit (evening only — an unlock already involved waiting).
      if (state.phase === "evening" && !passed) showGate();
    };
    if (document.body) onReady();
    else document.addEventListener("DOMContentLoaded", onReady, { once: true });

    setInterval(async () => {
      if (state && isWatching()) {
        const res = await send({ type: "watched", seconds: TICK_SECONDS });
        if (res) state.watchSeconds = res.watchSeconds;
      }
      refresh();
    }, TICK_SECONDS * 1000);
  }

  start();
})();
