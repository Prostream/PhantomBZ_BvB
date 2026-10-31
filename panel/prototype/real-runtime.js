"use strict";
// Runtime for the packaged app. Same interface as MockRuntime, but backed by panel/backend.py
// (served from the same origin; /api/status polled every 500 ms like the old panel) and by the
// native window (desktop/PhantomGladiator.cs) over chrome.webview messages for install, game launch
// and updates. The UI keeps the short unit ids of units.js; this file maps them to class paths.
const RealRuntime = (() => {
  const listeners = new Set();
  const emit = event => { for (const fn of listeners) fn(event || {}); };
  const fail = (code, detail = "") => Object.assign(new Error(detail || code), { code, detail });
  const webview = window.chrome && window.chrome.webview;
  const KEY_NAMES = ["spawn", "start", "stop", "refresh_catalog", "toggle_camera", "exit_camera", "cycle_team", "toggle_spectator"];
  const TEAMS = ["blue", "red", "neutral", "companion"];

  const s = {
    game: "offline",            // offline | connecting | notInMap | ready | mismatch
    gameRunning: false,
    appVersion: "",
    modVersion: "",             // build the running mod reports
    expectedBuild: "",          // build this app installs
    gamePath: "",
    blue: 0, red: 0, neutral: 0, companion: 0,
    down: { blue: 0, red: 0, neutral: 0, companion: 0 },
    companionFailures: 0,       // companions whose follow state or side did not read back (companion.lua)
    unreadable: 0,
    freeCam: false,
    team: "blue",
    spectator: false,
    spectatorPhase: "",
    statMatch: { enabled: false, baseline: null, matched: 0, failures: 0, reset: false },
    // spawn_difficulty_*: the level new units take (FOLLOW = the game's), the game's own level, counts.
    difficulty: { level: "FOLLOW", game: "", supported: false, failures: 0, skipped: 0, aiFailed: 0 },
    fight: "idle",
    winner: "",
    // arena_state after a cleanup the mod could not confirm: cleanup_pending / restore_pending need
    // another cleanup, spawn_uncertain needs a game restart. Spawning is blocked meanwhile.
    cleanup: "",
    keys: Object.fromEntries(KEY_NAMES.map(k => [k, null])),
    unitKeys: {},
    scan: null,
    synced: null,
    installed: false,
    components: null,
  };
  const jobs = [], jobById = new Map(), waiters = new Map();
  let csrf = "", owned = 0, launching = 0, failedPolls = 0;
  let teamRev = null, session = "", catalogKey = "", lastSig = {};
  let toGame = new Map(), toShort = new Map();

  // ---------- Native host ----------
  let rpcSeq = 0;
  const rpcWaiting = new Map(), progress = new Map();
  if (webview) {
    webview.addEventListener("message", e => {
      const m = e.data || {};
      if (m.reply) {
        const w = rpcWaiting.get(m.reply);
        if (!w) return;
        rpcWaiting.delete(m.reply);
        if (m.ok) w.resolve(m.result);
        else w.reject(Object.assign(fail(m.error?.code || "host", m.error?.message || ""), { tried: m.error?.tried || [] }));
      } else if (m.event === "progress") progress.get(m.task)?.(m);
      else if (m.event === "gameRunning" && s.gameRunning !== !!m.running) { s.gameRunning = !!m.running; emit({ type: "state", parts: new Set(["update"]) }); }
    });
  }
  function host(method, params = {}) {
    if (!webview) return Promise.reject(fail("noHost"));
    const id = ++rpcSeq;
    return new Promise((resolve, reject) => {
      rpcWaiting.set(id, { resolve, reject });
      webview.postMessage({ id, method, params });
    });
  }

  // ---------- Unit ids ----------
  const shortOf = path => toShort.get(path) || String(path || "").split("/").pop().split(".")[0];
  function gameId(short) {
    const id = toGame.get(short);
    if (!id) throw fail("unknownUnit");
    return id;
  }
  async function loadCatalog() {
    const r = await fetch("/api/catalog", { cache: "no-store" });
    if (!r.ok) return;
    const data = await r.json();
    const game = new Map(), short = new Map(), unitKeys = {};
    // Primary codex rows first, so a short name always means the entry units.js shows.
    const rows = [...(data.units || [])].sort((a, b) => (b.codex_entry_kind === "primary") - (a.codex_entry_kind === "primary"));
    for (const u of rows) {
      const name = u.internal_name || String(u.id).split("/").pop().split(".")[0];
      if (!game.has(name)) game.set(name, u.id);
      short.set(u.id, name);
      const k = u.unit_shortcut;
      if (k && k.key_code) unitKeys[name] = { code: k.key_code, mods: k.modifiers || 0, team: k.team || null, count: k.count || null };
    }
    toGame = game;
    toShort = short;
    s.unitKeys = unitKeys;
    s.synced = s.synced && { ...s.synced };
    emit({ type: "state", parts: new Set(["sel", "keys", "grid"]) });
  }

  // ---------- Status ----------
  function mapJob(q) {
    let j = jobById.get(q.id);
    const p = q.payload || {};
    if (!j) {
      j = { id: q.id, action: q.action, created: (q.created || Date.now() / 1000) * 1000 };
      jobById.set(q.id, j);
      jobs.push(j);
    }
    j.payload = { ...p, unit_id: p.unit_id ? shortOf(p.unit_id) : undefined };
    const status = q.status === "queued" || q.status === "pending" ? "pending" : q.status;
    const changed = j.status !== status;
    j.status = status;
    j.message = q.message || "";
    if (q.spawned_count != null) j.spawned = q.spawned_count;
    if (status !== "pending") j.finished = (q.completed || Date.now() / 1000) * 1000;
    // stat_match.lua reports through the ack text: a rolled-back match still spawns, an unconfirmed
    // rollback stops the batch and leaves that unit for cleanup.
    if (status === "succeeded" && /数值统一失败已回滚/.test(j.message)) j.warning = "matchFailed";
    if (status === "failed" && j.action === "spawn" && /数值统一/.test(j.message) && /清理/.test(j.message)) j.code = "matchAbort";
    // stop(): every unit removed ("待确认=0") but a restore record left for the next pass.
    if (status === "failed" && j.action === "stop" && /待确认=0/.test(j.message) && /恢复确认=false/.test(j.message) && !/生成结果未知/.test(j.message)) j.code = "restorePending";
    return changed ? j : null;
  }

  function apply(data) {
    csrf = data.csrf_token || csrf;
    const g = data.game || {}, v = g.values || {};
    const num = k => Number(v[k]) || 0, yes = k => v[k] === "true";
    const online = !!(g.online && g.game_session);
    if (online) launching = 0;
    const was = { game: s.game, blue: s.blue, red: s.red, neutral: s.neutral, soloHeld: s.neutral + s.down.neutral, fight: s.fight, freeCam: s.freeCam, phase: s.spectatorPhase, scanning: !!s.scan, base: s.statMatch.baseline };

    let game = online ? (g.ready ? "ready" : "notInMap") : launching && Date.now() - launching < 180000 ? "connecting" : "offline";
    s.modVersion = v.build || "";
    if (online && s.expectedBuild && s.modVersion && s.modVersion !== s.expectedBuild) game = "mismatch";
    s.game = game;

    if (online) {
      s.blue = num("blue_count");
      s.red = num("red_count");
      s.neutral = num("neutral_count");
      s.companion = num("companion_count");
      s.companionFailures = num("companion_failures");
      const soloDown = Math.max(0, num("neutral_owned_records") - s.neutral);
      const companionDown = Math.max(0, num("companion_owned_records") - s.companion);
      s.down = { blue: Math.max(0, num("arena_dead_count") - soloDown - companionDown), red: 0, neutral: soloDown, companion: companionDown };
      s.unreadable = num("arena_unreadable_count");
      // Companions stay through "stop and clear"; everything counted as the arena's leaves them out.
      owned = Math.max(0, num("arena_owned_records") - num("companion_owned_records"));
      s.freeCam = yes("arena_free_camera");
      s.spectator = yes("spectator_enabled");
      if (TEAMS.includes(v.current_team)) s.team = v.current_team;
      s.synced = v.current_unit ? { unit_id: shortOf(v.current_unit), team: v.current_team, count: num("current_count") } : null;
      const battle = v.arena_state === "battle_requested";
      s.fight = !battle ? "idle" : s.blue > 0 && s.red > 0 ? "fighting" : "ended";
      s.winner = s.fight === "ended" ? (s.blue ? "blue" : s.red ? "red" : "draw") : "";
      s.cleanup = ["cleanup_pending", "restore_pending", "spawn_uncertain"].includes(v.arena_state) ? v.arena_state : "";
      const m = s.statMatch, base = v.stat_match_baseline_unit;
      m.enabled = yes("stat_match_enabled");
      m.baseline = base ? { id: shortOf(base), hp: num("stat_match_health"), shachi: num("stat_match_shachi"), atk: num("stat_match_attack"), satk: num("stat_match_shachi_attack") } : null;
      m.matched = num("stat_match_count");
      m.failures = num("stat_match_failures");
      // stat_match.lua drops the baseline once the app holds no units; say so until something is summoned.
      if (base || !m.enabled) m.reset = false;
      else if (was.base && owned === 0) m.reset = true;
      const d = s.difficulty;
      d.supported = yes("spawn_difficulty_supported");
      if (DIFFICULTIES.includes(v.spawn_difficulty)) d.level = v.spawn_difficulty;
      d.game = v.spawn_difficulty_game || "";
      d.failures = num("spawn_difficulty_failures");
      d.skipped = num("spawn_difficulty_skipped");
      // ai_difficulty.lua reads its override back on every unit; a failure means stats changed but the AI did not.
      d.aiFailed = num("spawn_difficulty_ai_failed");
      s.scan = v.catalog_state === "scanning" ? { done: num("catalog_paths_done"), total: Math.max(1, num("catalog_paths_total")) } : null;
    } else {
      // Closing the game removes everything the mod spawned.
      Object.assign(s, { blue: 0, red: 0, neutral: 0, companion: 0, down: { blue: 0, red: 0, neutral: 0, companion: 0 }, unreadable: 0, freeCam: false, spectator: false, fight: "idle", winner: "", cleanup: "", synced: null, scan: null });
      Object.assign(s.statMatch, { baseline: null, matched: 0, failures: 0, reset: false });
      s.difficulty.game = "";
      owned = 0;
    }
    const toggling = jobs.some(j => j.action === "toggle_spectator" && j.status === "pending");
    const restoring = online && !s.spectator && (num("spectator_pending_relations") > 0 || num("spectator_pending_flags") > 0);
    s.spectatorPhase = restoring ? "restoring" : toggling ? (s.spectator ? "restoring" : "switching") : "";

    const bindings = data.function_keys?.bindings || {};
    for (const k of KEY_NAMES) s.keys[k] = bindings[k]?.key_code ? { code: bindings[k].key_code, mods: bindings[k].modifiers || 0 } : null;

    const changedJobs = (data.queue || []).map(mapJob).filter(Boolean);
    jobs.sort((a, b) => b.id - a.id);
    if (jobs.length > 100) for (const j of jobs.splice(100)) jobById.delete(j.id);

    // Catalog: once per session, after a scan, and when unit keys change.
    const key = [g.game_session || "", data.catalog?.total || 0, v.unit_keys_revision || "", v.unit_keys_epoch || ""].join("|");
    if (key !== catalogKey) { catalogKey = key; loadCatalog().catch(() => { catalogKey = ""; }); }

    // Events, in the same shapes MockRuntime sends.
    if (s.game !== was.game) emit({ type: "game" });
    for (const j of changedJobs) emit({ type: "job", job: j });
    for (const j of changedJobs) if (j.status !== "pending") waiters.get(j.id)?.(j);
    if (online && (g.game_session !== session)) { session = g.game_session; teamRev = null; }
    const rev = num("arena_team_revision");
    if (online && teamRev !== null && rev > teamRev) emit({ type: "teamKey", team: s.team });
    if (online) teamRev = rev;
    if (s.blue < was.blue || s.red < was.red) emit({ type: "casualty" });
    if (was.fight === "fighting" && s.fight === "ended") emit({ type: "fightEnd", winner: s.winner });
    if (s.neutral < was.neutral && s.neutral + s.down.neutral >= was.soloHeld) emit({ type: "soloDown" });
    if (s.freeCam !== was.freeCam) emit({ type: "freeCam" });
    if (was.phase === "restoring" && !s.spectator && !s.spectatorPhase) emit({ type: "spectator" });
    if (was.scanning && !s.scan) emit({ type: "scanDone" });
    else if (s.scan) emit({ type: "scan" });

    // Re-render only the parts whose data moved, so a 500 ms poll never resets what the player is doing.
    const sig = {
      topbar: [s.game, jobs.filter(j => j.status === "failed" || j.status === "uncertain").length],
      sel: [s.game, s.cleanup, s.team, JSON.stringify(s.synced), s.spectator, s.statMatch.enabled, s.statMatch.baseline?.id, s.keys.spawn?.code, s.keys.spawn?.mods],
      solo: [s.game, s.neutral, s.down.neutral, s.spectator, s.spectatorPhase, s.freeCam],
      companion: [s.game, s.companion, s.down.companion, s.companionFailures],
      match: [s.game, JSON.stringify(s.statMatch)],
      diff: [s.game, JSON.stringify(s.difficulty)],
      battle: [s.game, s.cleanup, s.blue, s.red, s.neutral, s.down.blue, s.down.neutral, s.unreadable, s.fight, owned, JSON.stringify([s.keys.start, s.keys.stop])],
      view: [s.game, s.spectator, s.spectatorPhase, s.freeCam, JSON.stringify([s.keys.toggle_camera, s.keys.toggle_spectator])],
      keys: [s.game, JSON.stringify(s.keys)],
      settings: [s.game, JSON.stringify(s.scan)],
    };
    const parts = new Set(Object.keys(sig).filter(k => JSON.stringify(sig[k]) !== JSON.stringify(lastSig[k])));
    lastSig = sig;
    if (parts.size) emit({ type: "state", parts });
  }

  async function poll() {
    try {
      const r = await fetch("/api/status", { cache: "no-store" });
      if (!r.ok) throw new Error(String(r.status));
      failedPolls = 0;
      apply(await r.json());
    } catch {
      // The native window restarts the backend when the game folder changes; ride out short gaps.
      if (++failedPolls === 4) apply({ game: {}, queue: [] });
    }
    setTimeout(poll, 500);
  }

  // ---------- Commands ----------
  const online = () => ["notInMap", "ready", "mismatch"].includes(s.game);
  const ready = () => s.game === "ready" || s.game === "mismatch";
  const DIFFICULTIES = ["FOLLOW", "EASY", "NORMAL", "HARD", "NIGHTMARE"];
  const wireKey = b => (b ? { key_code: b.code, modifiers: b.mods || 0 } : { key_code: 0, modifiers: 0 });

  async function command(action, payload = {}) {
    if (!online()) throw fail("offline");
    if (["spawn", "start", "toggle_spectator"].includes(action) && !ready()) throw fail("notInMap");
    if (action === "toggle_camera" && !s.freeCam && !ready()) throw fail("notInMap");
    let path = "/api/command", body;
    if (action === "spawn" || action === "select_unit") body = { action, unit_id: gameId(payload.unit_id), team: payload.team, count: payload.count };
    else if (action === "configure_unit_key") {
      body = { action, unit_id: gameId(payload.unit_id), key_code: payload.code || 0, modifiers: payload.code ? payload.mods || 0 : 0 };
      if (payload.code && payload.team) Object.assign(body, { team: payload.team, count: payload.count });
    }
    else if (action === "set_spawn_difficulty") body = { action, difficulty: payload.difficulty };
    else if (action === "configure_keys") { path = "/api/keybinds"; body = Object.fromEntries(KEY_NAMES.map(k => [k, wireKey(payload.bindings[k])])); }
    else body = { action };
    const held = action === "stop" ? owned : action === "clear_neutral" ? s.neutral + s.down.neutral : 0;
    const companionsHeld = action === "dismiss_companions" ? s.companion + s.down.companion : 0;
    const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf }, body: JSON.stringify(body) });
    const reply = await r.json().catch(() => ({}));
    if (!r.ok) throw fail("rejected", reply.error || "");
    // Show it in the history right away; the status poll fills in the game's answer.
    // A poll may already have picked the job up (and even its answer); never step it back to pending.
    const job = jobById.get(reply.id) || mapJob({ id: reply.id, action, payload: body, status: "pending", created: Date.now() / 1000 });
    jobs.sort((a, b) => b.id - a.id);
    emit({ type: "job", job });
    const done = await new Promise(resolve => {
      const timer = setTimeout(() => { waiters.delete(job.id); resolve(null); }, action === "refresh_catalog" ? 20000 : 90000);
      waiters.set(job.id, j => { clearTimeout(timer); waiters.delete(job.id); resolve(j); });
      if (job.status !== "pending") waiters.get(job.id)(job);
    });
    if (!done) return { ...job, status: "uncertain", code: "noAck" };
    if (held) done.cleared = Math.max(0, held - owned);
    // arena_controller.lua answers "随从清理：已确认=N"; fall back to the counts before and after.
    if (action === "dismiss_companions") done.cleared = Number((done.message || "").match(/已确认=(\d+)/)?.[1] ?? Math.max(0, companionsHeld - s.companion - s.down.companion));
    // The mod saved and read the choice back; show it before the next poll does.
    if (action === "set_spawn_difficulty" && done.status === "succeeded") s.difficulty.level = payload.difficulty;
    return done;
  }

  function launchGame() {
    if (online() || s.game === "connecting") return;
    launching = Date.now();
    s.game = "connecting";
    emit({ type: "game" });
    host("launchGame").catch(() => { launching = 0; s.game = "offline"; emit({ type: "game" }); });
  }

  function trackProgress(task, onProgress) {
    progress.set(task, onProgress);
    return () => progress.delete(task);
  }

  const setup = {
    detectGame: () => host("detectGame"),
    pickFolder: () => host("pickFolder"),
    async setGamePath(path) {
      const info = await host("setGamePath", { path });
      s.gamePath = info.path;
      return info;
    },
    async components() {
      const list = await host("components");
      s.components = list;
      s.installed = list.every(c => c.ok);
      return list;
    },
    async install(onProgress) {
      const stop = trackProgress("install", m => onProgress({ step: m.step, ratio: m.ratio }));
      try { await host("install"); } finally { stop(); }
      await setup.components();
    },
  };

  const update = {
    check: () => host("checkUpdate", { lang: (document.documentElement.lang || "zh").slice(0, 2) }),
    download(lineId, size, onProgress) {
      const stop = trackProgress("download", m => onProgress({ done: m.done, total: m.total || size, speed: m.speed || 0 }));
      const promise = host("downloadUpdate", { line: lineId }).finally(stop);
      return { promise, cancel() { host("cancelDownload").catch(() => {}); } };
    },
    verify: () => host("verifyUpdate"),
    install: () => host("installUpdate"),
    restart: () => host("restart"),
  };

  host("info").then(info => {
    s.appVersion = info.appVersion;
    s.expectedBuild = info.modBuild;
    s.gamePath = info.gamePath || "";
    s.gameRunning = !!info.gameRunning;
    emit({ type: "host" });
    if (info.gamePath) setup.components().then(() => emit({ type: "host" }), () => {});
  }).catch(() => {});
  poll();

  return {
    demo: false,
    hasHost: !!webview,
    state: s,
    jobs,
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    online,
    ready,
    owned: () => owned,
    command,
    launchGame,
    setup,
    update,
    openFolder: () => host("openFolder"),
    exportReport: () => host("exportReport"),
    // Prototype demo hooks; the packaged app has no demo panel.
    setGame() {}, cycleTeam() {}, defeatSolo() {}, toggleFreeCam() {}, set() {},
  };
})();
window.PGRuntime = RealRuntime;
