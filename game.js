// Stand Clear v2: the game runs on your actual ride.
// At a station the shop is open. Between stations your crew fights waves until the doors open.
// "Where am I" comes from GPS (near a station on your line) and the network
// (signal dies in the tunnel, comes back at the next stop). Everything can be mocked: ?mock=1.

const DATA = await fetch('stations.json').then(r => r.json());
const $ = s => document.querySelector(s);
const app = $('#app');
const now = () => Date.now();
const rnd = n => Math.floor(Math.random() * n);
const pick = a => a[rnd(a.length)];
const MOCK = new URLSearchParams(location.search).has('mock');

// ---------------------------------------------------------------- units
const UNITS = {
  rat:      { name:'Rat',             e:'🐀', atk:1, hp:2, cost:2, ab:'faint_rat',     text:'Faint: leaves a 1/1 baby rat.' },
  pigeon:   { name:'Pigeon',          e:'🐦', atk:2, hp:1, cost:2, ab:'start_snipe',   text:'Each wave: 1 dmg to a random enemy.' },
  dancer:   { name:'Showtime Dancer', e:'🕺', atk:2, hp:3, cost:3, ab:'hurt_rage',     text:'Hurt: +1 atk. WHAT TIME IS IT' },
  mariachi: { name:'Mariachi Band',   e:'🎺', atk:1, hp:4, cost:3, ab:'start_team_atk',text:'Each wave: friends +1 atk (this wave).' },
  spreader: { name:'Manspreader',     e:'🧍', atk:1, hp:7, cost:3, ab:'tank',          text:'Takes 1 less damage. Takes two seats.' },
  conductor:{ name:'Conductor',       e:'👷', atk:3, hp:2, cost:3, ab:'faint_team_hp', text:'Faint: friends +2 hp.' },
  churro:   { name:'Churro Lady',     e:'🥨', atk:2, hp:3, cost:3, ab:'wave_heal',     text:'Wave cleared: friends heal 2.' },
  preacher: { name:'Subway Preacher', e:'📢', atk:2, hp:4, cost:4, ab:'start_debuff',  text:'Each wave: enemies -1 atk.' },
  cop:      { name:'MTA Cop',         e:'👮', atk:4, hp:5, cost:5, ab:'none',          text:'Just stands there. Strong though.' },
  ratking:  { name:'Rat King',        e:'👑', atk:3, hp:4, cost:5, ab:'faint_rats2',   text:'Faint: two 2/2 rats.' },
  cat:      { name:'Bodega Cat',      e:'🐈', atk:3, hp:3, cost:3, ab:'start_behind',  text:'Each wave: friend behind +1/+1 for good.' },
  // borough exclusives: only sold in that borough
  elmo:     { name:'Times Sq Elmo',   e:'🧸', atk:3, hp:5, cost:4, ab:'wave_gold',     text:'Wave cleared: +1 gold. Wants a tip.', b:'M' },
  courier:  { name:'Bike Courier',    e:'🚲', atk:4, hp:2, cost:4, ab:'start_backline',text:'Each wave: hits the last enemy for 3.', b:'Bk' },
  foodcart: { name:'Food Cart',       e:'🌮', atk:2, hp:5, cost:4, ab:'wave_heal_all', text:'Wave cleared: friends fully heal.', b:'Q' },
  fan:      { name:'Yankees Fan',     e:'🧢', atk:3, hp:4, cost:4, ab:'hurt_team',     text:'Hurt: friends +1 atk (this ride).', b:'Bx' },
  ferry:    { name:'Ferry Commuter',  e:'⛴️', atk:2, hp:6, cost:4, ab:'start_all',     text:'Each wave: friends +1/+1 (this ride). Rare.', b:'SI' },
};
const COMMON = ['rat','pigeon','dancer','mariachi','spreader','conductor','churro','preacher','cop','ratking'];
const BORO = { M:'elmo', Bk:'courier', Q:'foodcart', Bx:'fan', SI:'ferry' };
const BORO_NAME = { M:'Manhattan', Bk:'Brooklyn', Q:'Queens', Bx:'the Bronx', SI:'Staten Island' };
let uid = 0;
function mk(key, bonus = 0) {
  const b = UNITS[key];
  return { uid: ++uid, key, atk: b.atk + bonus, hp: b.hp + bonus, max: b.hp + bonus, lvl: 1, tmp: 0 };
}
const info = u => UNITS[u.key];

// ---------------------------------------------------------------- stations
const ST = DATA.stations;
const station = sid => ST[sid];
function dist(a, b) { // meters
  const R = 6371e3, r = x => x * Math.PI / 180;
  const dl = r(b.lat - a.lat), dn = r(b.lon - a.lon);
  const h = Math.sin(dl/2)**2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dn/2)**2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
function hash(s) { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
const isRush = () => { const d = new Date(), h = d.getHours(), wk = d.getDay() % 6 !== 0; return wk && ((h >= 7 && h < 10) || (h >= 16 && h < 19)); };
const isLate = () => { const h = new Date().getHours(); return h >= 0 && h < 5; };

// Every station's shop comes from what the station actually is.
const NAMED = {
  'Bedford Av':            { k:'thrift',  name:'Thrift store',  text:'One unit is free. The rest are mystery boxes.' },
  'Canal St':              { k:'knockoff',name:'Knockoffs',     text:'Everything costs 1. Everything has -1 hp.' },
  'Times Sq-42 St':        { k:'chaos',   name:'Total chaos',   text:'+3 gold. The shop restocks after every purchase.' },
  '34 St-Herald Sq':       { k:'chaos',   name:'Herald Sq rush',text:'+3 gold. The shop restocks after every purchase.' },
  'Coney Island-Stillwell Av': { k:'boardwalk', name:'Boardwalk', text:'Everything half off. The ocean is right there.' },
  '161 St-Yankee Stadium': { k:'stadium', name:'Game day',      text:'Yankees Fans are free.' },
  'Flushing-Main St':      { k:'feast',   name:'Food crawl',    text:'Your whole crew gets +2 max hp, for good.' },
  'Jackson Hts-Roosevelt Av': { k:'feast',name:'Food crawl',    text:'Your whole crew gets +2 max hp, for good.' },
  'Myrtle-Wyckoff Avs':    { k:'bodega',  name:'Bodega',        text:'A Bodega Cat is in stock.' },
};
function traits(sid, route) {
  const s = station(sid), stops = DATA.routes[route].stops, out = [];
  if (NAMED[s.n]) out.push(NAMED[s.n]);
  if (sid === stops[0] || sid === stops[stops.length - 1]) out.push({ k:'terminal', name:'Last stop', text:'Everybody off. Get a swipe back.' });
  if (s.x.length >= 4) out.push({ k:'hub', name:`Transfer hub (${s.x.length} lines)`, text:`The shop has ${Math.min(7, 3 + Math.floor(s.x.length / 2))} slots.` });
  if (s.cbd) out.push({ k:'cbd', name:'Congestion pricing', text:'Prices +1, but +2 gold.' });
  if (s.st && s.st !== 'Subway') out.push({ k:'sky', name:`Daylight (${s.st.toLowerCase()})`, text:'Fresh air: crew +1 atk for the next ride.' });
  if (s.ada) out.push({ k:'elevator', name:'Elevator', text: (hash(s.n + new Date().toDateString()) % 3) ? 'Works today: rerolls are free.' : 'Out of service today, as usual.' , works: !!(hash(s.n + new Date().toDateString()) % 3) });
  if (!out.some(t => t.k === 'bodega') && hash(sid) % 4 === 0) out.push({ k:'bodega', name:'Bodega upstairs', text:'A Bodega Cat is in stock.' });
  if (s.b && BORO[s.b]) out.push({ k:'boro', name:BORO_NAME[s.b], text:`${UNITS[BORO[s.b]].e} ${UNITS[BORO[s.b]].name} only shows up here.` });
  if (isRush()) out.push({ k:'rush', name:'Rush hour', text:'Bigger waves, +1 gold per wave.' });
  if (isLate()) out.push({ k:'late', name:'Late night', text:'Weird waves. Nobody is checking fares.' });
  return out;
}
const has = (k) => S.traits?.some(t => t.k === k && t.works !== false);

// ---------------------------------------------------------------- sensors
// Sensors only report raw facts. Presence (below) decides what they mean.
const Sensors = {
  online: true, pos: null, // pos = {lat, lon, acc, at}
  gpsState: 'off', mock: MOCK,
  start() {
    if (this.mock) return;
    if ('geolocation' in navigator) {
      this.gpsState = 'asking';
      navigator.geolocation.watchPosition(p => {
        this.gpsState = 'on';
        this.pos = { lat: p.coords.latitude, lon: p.coords.longitude, acc: p.coords.accuracy, at: now() };
        Presence.update();
      }, () => { this.gpsState = 'denied'; render(); }, { enableHighAccuracy: true, maximumAge: 10000, timeout: 20000 });
    }
    addEventListener('online', () => this.probe());
    addEventListener('offline', () => { this.set(false); });
    setInterval(() => this.probe(), 8000);
    this.probe();
  },
  async probe() { // navigator.onLine lies in tunnels, so actually try to fetch something tiny
    if (this.mock) return;
    const c = new AbortController(); const t = setTimeout(() => c.abort(), 4000);
    try { await fetch('ping.txt?' + now(), { cache: 'no-store', signal: c.signal }); this.set(true); }
    catch { this.set(false); }
    clearTimeout(t);
  },
  set(on) { if (on !== this.online) { this.online = on; Presence.update(); render(); } },
  fresh() { return this.pos && now() - this.pos.at < 30000 && this.pos.acc <= 250; },
};

// ---------------------------------------------------------------- presence
// phase 'station': doors open, shop open.  phase 'riding': between stations, fighting.
const Presence = {
  nearestOnRoute() {
    if (!S || !Sensors.fresh()) return null;
    let best = null;
    S.stops.forEach((sid, i) => { const d = dist(Sensors.pos, station(sid)); if (!best || d < best.d) best = { i, d }; });
    return best;
  },
  update() {
    if (!S || S.over || !S.dir) return;
    const near = this.nearestOnRoute(), t = now();
    if (!Sensors.online && !S.offlineAt) S.offlineAt = t;
    if (Sensors.online && S.phase === 'station') S.offlineAt = null;
    if (S.phase === 'station') {
      if (near && near.d < 200 && near.i !== S.idx) { depart('gps'); arrive(near.i, 'gps'); return; }
      if (near && near.d > 450) return depart('gps');
      if (!Sensors.online && t - S.phaseAt > 15000) return depart('signal lost');
    } else {
      if (near && near.d < 200 && near.i !== S.fromIdx) return arrive(near.i, 'gps');
      if (Sensors.online && S.offlineAt && t - S.offlineAt > 20000 && t - S.phaseAt > 25000) return arrive(S.fromIdx + S.dir, 'signal back');
    }
  },
};

// ---------------------------------------------------------------- run state
let S = load();
function save() { if (S) localStorage.setItem('run', JSON.stringify(S)); else localStorage.removeItem('run'); }
function load() { try { const s = JSON.parse(localStorage.getItem('run')); if (s) uid = 1e6; return s; } catch { return null; } }

function newRun(route, idx, dir) {
  S = { route, stops: DATA.routes[route].stops, idx, dir, phase: 'station', phaseAt: now(), gold: 0, swipes: 3,
        team: [], shop: [], sel: null, legs: 0, waves: 0, earned: 0, log: [], fight: null, offlineAt: null, started: now(), skyBuff: 0 };
  enterStation(idx, true);
}

function enterStation(i, first = false) {
  S.idx = Math.max(0, Math.min(S.stops.length - 1, i));
  S.phase = 'station'; S.phaseAt = now(); S.offlineAt = null; S.fight = null;
  S.traits = traits(S.stops[S.idx], S.route);
  const income = 8 + (has('chaos') ? 3 : 0) + (has('cbd') ? 2 : 0);
  S.gold += income;
  if (has('terminal') && !first) S.swipes = Math.min(3, S.swipes + 1);
  S.team = S.team.filter(u => !u.summoned); // rats from the last ride get off here
  S.team.forEach(u => { u.tmp = 0; u.gone = false; u.hit = false; if (has('feast')) u.max += 2; u.hp = u.max; });
  S.skyBuff = has('sky') ? 1 : 0;
  // at the end of the line you turn around
  if (S.idx + S.dir < 0 || S.idx + S.dir >= S.stops.length) S.dir = -S.dir;
  stock();
  note(`🚪 ${station(S.stops[S.idx]).n}. +${income} gold.`);
  save(); render();
}

function slots() { const h = S.traits.find(t => t.k === 'hub'); return h ? Math.min(7, 3 + Math.floor(station(S.stops[S.idx]).x.length / 2)) : 4; }
function price(u) {
  if (u.free) return 0;
  if (has('knockoff')) return 1;
  let p = UNITS[u.key].cost;
  if (has('stadium') && u.key === 'fan') return 0;
  if (has('boardwalk')) p = Math.ceil(p / 2);
  if (has('cbd')) p++;
  return p;
}
function stock() {
  const tier = Math.min(COMMON.length, 6 + Math.floor(S.legs / 2));
  S.shop = [];
  for (let k = 0; k < slots(); k++) {
    const u = mk(pick(COMMON.slice(0, tier)));
    if (has('knockoff')) { u.hp = u.max = Math.max(1, u.max - 1); }
    if (has('thrift')) u.mystery = true;
    S.shop.push(u);
  }
  const b = station(S.stops[S.idx]).b;
  if (BORO[b] && Math.random() < (has('boro') ? 0.6 : 0)) S.shop[S.shop.length - 1] = mk(BORO[b]);
  if (has('stadium')) S.shop[S.shop.length - 1] = mk('fan');
  if (has('bodega')) S.shop[0] = mk('cat');
  if (has('thrift')) pick(S.shop).free = true;
}

function buy(k) {
  const u = S.shop[k], p = price(u);
  if (S.gold < p) return;
  const same = S.team.find(t => t.key === u.key);
  if (same) { same.atk++; same.max++; same.hp = same.max; same.lvl++; }
  else if (S.team.length < 5) { delete u.mystery; delete u.free; S.team.push(u); }
  else return note('Car is full (5). Sell someone first.');
  S.gold -= p; S.shop.splice(k, 1);
  if (has('chaos')) stock();
  save(); render();
}
function sell(k) { S.gold += S.team[k].lvl; S.team.splice(k, 1); S.sel = null; save(); render(); }
function select(k) {
  if (S.sel === null) S.sel = k;
  else { const a = S.team[S.sel]; S.team.splice(S.sel, 1); S.team.splice(k, 0, a); S.sel = null; }
  save(); render();
}
function reroll() { const c = has('elevator') ? 0 : 1; if (S.gold < c) return; S.gold -= c; stock(); save(); render(); }

// ---------------------------------------------------------------- riding + fighting
function depart(why) {
  if (S.phase !== 'station') return;
  S.phase = 'riding'; S.phaseAt = now(); S.fromIdx = S.idx;
  S.fight = { wave: 0, enemies: [], wiped: false, lastTick: now(), pause: 0, legGold: 0 };
  S.team.forEach(u => { u.tmp = S.skyBuff; });
  note(`🚇 Doors closed (${why}). Next stop ${station(S.stops[S.idx + S.dir]).n}.`);
  if (!S.team.length) { S.fight.wiped = true; note('Nobody in your car. You just ride.'); }
  else nextWave();
  wakeLock(true); save(); render();
}

function arrive(i, why) {
  if (S.phase !== 'riding') return;
  const f = S.fight;
  S.legs++;
  if (!f.wiped && S.team.length) { S.gold += 3; S.earned += 3; note(`✅ Survived the ride (+3). Doors opening (${why}).`); }
  else note(`Doors opening (${why}).`);
  if (f.enemies.some(e => e.hp > 0)) note('The rest of the wave gets off. Cowards.');
  if (S.dir === 0 || (i - S.fromIdx) * S.dir < 0) S.dir = Math.sign(i - S.fromIdx) || S.dir; // GPS says we went the other way
  wakeLock(false);
  enterStation(i);
}

function nextWave() {
  const f = S.fight; f.wave++;
  const power = S.legs + f.wave - 1;
  const n = Math.min(5, 1 + Math.floor(power / 3) + (isRush() ? 1 : 0));
  const pool = isLate() ? ['rat', 'ratking', 'preacher', 'dancer', 'pigeon'] : COMMON.slice(0, Math.min(COMMON.length, 4 + power));
  f.enemies = Array.from({ length: n }, () => mk(pick(pool), Math.floor(power / 3)));
  f.pause = 0;
  waveStart(S.team, f.enemies);
  waveStart(f.enemies, S.team);
  note(`⚔️ Wave ${f.wave}: ${f.enemies.map(e => info(e).e).join('')}`);
}
const alive = t => t.filter(u => u.hp > 0);
const atk = u => Math.max(0, u.atk + (u.tmp || 0));
function waveStart(mine, foes) {
  for (const u of alive(mine)) {
    const a = info(u).ab;
    if (a === 'start_snipe' && alive(foes).length) hurt(pick(alive(foes)), u.lvl, foes);
    if (a === 'start_team_atk') mine.forEach(x => x !== u && (x.tmp = (x.tmp || 0) + 1));
    if (a === 'start_debuff') foes.forEach(x => x.tmp = (x.tmp || 0) - 1);
    if (a === 'start_behind') { const b = mine[mine.indexOf(u) + 1]; if (b) { b.atk++; b.max++; b.hp++; } }
    if (a === 'start_backline' && alive(foes).length) hurt(alive(foes).at(-1), 3, foes);
    if (a === 'start_all') mine.forEach(x => { x.tmp = (x.tmp || 0) + 1; x.hp++; });
  }
  cleanup(mine); cleanup(foes);
}
function hurt(u, d, team) {
  if (info(u).ab === 'tank') d = Math.max(1, d - 1);
  u.hp -= d; u.hit = true;
  if (u.hp > 0 && info(u).ab === 'hurt_rage') u.tmp = (u.tmp || 0) + 1;
  if (u.hp > 0 && info(u).ab === 'hurt_team') team.forEach(x => x !== u && (x.tmp = (x.tmp || 0) + 1));
}
function cleanup(team) {
  for (let k = 0; k < team.length; k++) {
    const u = team[k];
    if (u.hp > 0 || u.gone) continue;
    u.gone = true;
    const a = info(u).ab, mine = team === S.team;
    if (a === 'faint_rat') team.splice(k + 1, 0, { ...mk('rat'), atk: 1, hp: 1, max: 1, summoned: true, keyName: 'Baby Rat' });
    if (a === 'faint_rats2') for (let j = 0; j < 2; j++) team.splice(k + 1, 0, { ...mk('rat'), atk: 2, hp: 2, max: 2, summoned: true });
    if (a === 'faint_team_hp') alive(team).forEach(x => x.hp += 2);
    if (mine && u.summoned) { team.splice(k, 1); k--; }
  }
}

function tick() { // one exchange of blows; called once a second, and caught up after the phone sleeps
  const f = S.fight;
  if (!f || f.wiped) return;
  if (f.pause > 0) { f.pause--; if (!f.pause) nextWave(); return; }
  const a = alive(S.team)[0], e = alive(f.enemies)[0];
  if (!a || !e) return;
  hurt(e, atk(a), f.enemies); hurt(a, atk(e), S.team);
  cleanup(S.team); cleanup(f.enemies);
  if (!alive(f.enemies).length) {
    const g = 2 + Math.floor(f.wave / 2) + (isRush() ? 1 : 0) + S.team.filter(u => info(u).ab === 'wave_gold').length;
    S.gold += g; S.earned += g; S.waves++; f.legGold += g;
    S.team.forEach(u => { const ab = info(u).ab; if (ab === 'wave_heal') S.team.forEach(x => x.hp = Math.min(x.max, x.hp + 2)); if (ab === 'wave_heal_all') S.team.forEach(x => x.hp = x.max); });
    note(`🏆 Wave ${f.wave} cleared, +${g} gold.`);
    f.pause = 3;
  } else if (!alive(S.team).length) {
    f.wiped = true; S.swipes--;
    S.team = S.team.filter(u => !u.summoned).map(u => (u.gone = false, u.hp = 1, u));
    note(S.swipes > 0 ? `💀 Your crew got wiped. -1 swipe (${S.swipes} left). You lie on the floor until the doors open.` : '💀 Out of swipes.');
    if (S.swipes <= 0) return end(false);
  }
}
setInterval(() => {
  if (!S || S.over || S.phase !== 'riding' || !S.fight) return;
  const due = Math.min(600, Math.floor((now() - S.fight.lastTick) / 1000 * speed()));
  for (let k = 0; k < due && !S.over; k++) tick();
  if (due) { S.fight.lastTick = now(); save(); render(); S.team.forEach(u => u.hit = false); S.fight?.enemies.forEach(u => u.hit = false); }
  Presence.update();
}, 250);

function note(t) { S.log.push(t); S.log = S.log.slice(-40); }

let lock = null;
async function wakeLock(on) { try { if (on && !lock) lock = await navigator.wakeLock?.request('screen'); if (!on && lock) { lock.release(); lock = null; } } catch {} }

// ---------------------------------------------------------------- end of run + fridge
const FRIDGE_URL = new URLSearchParams(location.search).get('fridge');
function end(exited) {
  S.over = true;
  const r = { line: S.route, exitedAt: station(S.stops[S.idx]).n, exited, legs: S.legs, waves: S.waves, gold: S.earned,
              crew: S.team.map(u => `${info(u).e}${u.atk}/${u.max}`).join(' '), at: new Date().toISOString() };
  r.message = `${exited ? '🚶' : '💀'} ${r.line} train: ${r.legs} stops, ${r.waves} waves, ${r.gold} gold. ${exited ? 'Got off at' : 'Wiped near'} ${r.exitedAt}. ${r.crew}`;
  const runs = JSON.parse(localStorage.getItem('runs') || '[]'); runs.unshift(r); localStorage.setItem('runs', JSON.stringify(runs.slice(0, 20)));
  console.log('[fridge]', r.message);
  if (FRIDGE_URL) fetch(FRIDGE_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(r) }).catch(() => {});
  S.result = r; wakeLock(false); save(); render();
}

// ---------------------------------------------------------------- mock panel
const Mock = { speed: 1, auto: false, autoAt: 0, autoStage: 0 };
const speed = () => (MOCK ? Mock.speed : 1);
function mockGps(sid) { Sensors.pos = sid ? { ...station(sid), acc: 30, at: now() } : null; Presence.update(); render(); }
function mockNet(on) { Sensors.online = on; Presence.update(); render(); }
setInterval(() => { // auto-ride: 20s at the station with signal, 45s in the tunnel without, then signal + GPS at the next stop
  if (!MOCK || !Mock.auto || !S || S.over) return;
  const el = (now() - Mock.autoAt) * Mock.speed;
  if (S.phase === 'station' && el > 20000) { Mock.autoAt = now(); mockNet(false); mockGps(null); }
  else if (S.phase === 'riding' && el > 45000) { Mock.autoAt = now(); mockNet(true); mockGps(S.stops[S.fromIdx + S.dir]); }
  if (Sensors.pos) Sensors.pos.at = now();
}, 250);

// ---------------------------------------------------------------- rendering
function bullet(r, big) { const x = DATA.routes[r]; return `<span class="bullet ${big ? 'big' : ''}" style="background:${x.color};color:${x.text}">${r.replace('S', 'S')}</span>`; }
function unitHTML(u, extra = '') {
  const i = info(u), m = u.mystery;
  return `<div class="unit ${u.hp <= 0 ? 'dead' : ''} ${u.hit ? 'hit' : ''}">${u.lvl > 1 ? `<span class="lvl">★${u.lvl}</span>` : ''}
    <div class="e">${m ? '📦' : i.e}</div><div class="nm">${m ? '???' : (u.keyName || i.name)}</div>
    <div class="s">${m ? '?/?' : `${atk(u)}⚔️ ${Math.max(0, u.hp)}${u.max ? '/' + u.max : ''}❤️`}</div>
    <div class="ab">${m ? 'mystery box' : i.text}</div>${extra}</div>`;
}
function statusBar() {
  const gps = Sensors.mock ? (Sensors.pos ? '📍mock' : '📍—') : ({ on: Sensors.fresh() ? '📍' : '📍~', asking: '📍?', denied: '📍✕', off: '📍✕' })[Sensors.gpsState];
  return `<div class="hud">${bullet(S.route)} <span>💰${S.gold}</span><span>🎫${'●'.repeat(Math.max(0,S.swipes))}${'○'.repeat(Math.max(0,3 - S.swipes))}</span><span>${Sensors.online ? '📶' : '🚫📶'}</span><span>${gps}</span><span class="dim">${S.legs} stops · ${S.waves} waves</span></div>`;
}
function lineMap() {
  const lo = Math.max(0, S.idx - 3), hi = Math.min(S.stops.length, S.idx + 4);
  return `<div class="strip">${S.stops.slice(lo, hi).map((sid, k) => { const i = lo + k;
    const cls = i === S.idx ? (S.phase === 'station' ? 'here' : 'left') : (S.phase === 'riding' && i === S.idx + S.dir ? 'next' : '');
    return `<div class="sn ${cls}"><div class="dot"></div><div>${station(sid).n}</div></div>`; }).join('')}</div>`;
}
function logHTML() { return `<div class="log" id="log">${S.log.slice(-12).map(l => `<div>${l}</div>`).join('')}</div>`; }

function render() {
  if (!S) return renderStart();
  if (S.result) return renderEnd();
  const here = station(S.stops[S.idx]);
  let h = statusBar() + lineMap();
  if (S.phase === 'station') {
    h += `<h1>${here.n}</h1>
      <div class="traits">${S.traits.map(t => `<div class="trait"><b>${t.name}</b> ${t.text}</div>`).join('')}</div>
      <h2>Shop</h2><div class="row">${S.shop.map((u, k) => unitHTML(u, `<button onclick="G.buy(${k})" ${S.gold < price(u) ? 'disabled' : ''}>${price(u) ? '💰' + price(u) : 'FREE'}</button>`)).join('')}</div>
      <button onclick="G.reroll()">🔄 Restock (${has('elevator') ? 'free' : '💰1'})</button>
      <h2>Your car ${S.team.length}/5 <span class="dim">front is left · tap two to swap</span></h2>
      <div class="row">${S.team.map((u, k) => unitHTML(u, `<button onclick="G.select(${k})" class="${S.sel === k ? 'on' : ''}">${S.sel === k ? 'moving…' : 'move'}</button><button onclick="G.sell(${k})">sell ${u.lvl}</button>`)).join('') || '<span class="dim">Empty car. Buy someone before the doors close.</span>'}</div>
      <p class="dim">Next: ${station(S.stops[S.idx + S.dir]).n}. Waves start when you leave. GPS or losing signal will notice.</p>
      <button class="go" onclick="G.depart()">🚪 Doors closed → ride</button> <button onclick="G.exit()">🚶 Exit the system</button>`;
  } else {
    const f = S.fight, nxt = station(S.stops[S.fromIdx + S.dir]);
    h += `<h1>→ ${nxt ? nxt.n : '?'}</h1>
      <div class="dim">${f.wiped ? 'Down for this ride. Waiting for the doors.' : f.pause ? `Wave ${f.wave + 1} boarding…` : `Wave ${f.wave}`} · ${Math.round((now() - S.phaseAt) / 1000)}s in the tunnel</div>
      <div class="row">${(f.enemies || []).map(u => unitHTML(u)).join('')}</div><div class="vs">vs</div>
      <div class="row">${S.team.map(u => unitHTML(u)).join('')}</div>
      ${logHTML()}
      <button class="go" onclick="G.arrive()">🚪 We're at ${nxt ? nxt.n : 'the next stop'}</button>`;
  }
  if (S.phase === 'station') h += logHTML();
  h += mockPanel();
  app.innerHTML = h;
  const lg = $('#log'); if (lg) lg.scrollTop = lg.scrollHeight;
}

function mockPanel() {
  if (!MOCK) return '';
  const cur = S ? S.stops : [];
  return `<div class="mock"><b>🧪 mock sensors</b><br>
    <label><input type="checkbox" ${Sensors.online ? 'checked' : ''} onchange="G.mockNet(this.checked)"> signal</label>
    <select onchange="G.mockGps(this.value)"><option value="">GPS: none (tunnel)</option>${cur.map(sid => `<option value="${sid}" ${Sensors.pos && Sensors.pos.lat === station(sid).lat ? 'selected' : ''}>GPS at ${station(sid).n}</option>`).join('')}</select>
    <label><input type="checkbox" ${Mock.auto ? 'checked' : ''} onchange="G.mockAuto(this.checked)"> auto-ride</label>
    speed <select onchange="G.mockSpeed(+this.value)">${[1, 5, 20].map(x => `<option ${Mock.speed === x ? 'selected' : ''}>${x}</option>`).join('')}</select>
    <button onclick="G.reset()">reset run</button></div>`;
}

let startRoute = null, startIdx = null;
function renderStart() {
  const near = Sensors.fresh() ? Object.entries(ST).map(([sid, s]) => ({ sid, d: dist(Sensors.pos, s) })).sort((a, b) => a.d - b.d)[0] : null;
  const nearRoutes = near && near.d < 300 ? Object.keys(DATA.routes).filter(r => DATA.routes[r].stops.includes(near.sid)) : [];
  let h = `<h1>🚇 Stand Clear</h1><div class="dim">Hop on a train. Between stops your crew fights whatever boards. At every stop the shop opens, and every station's shop is different. Keep the tab open while you ride.</div>`;
  h += `<h2>What train are you on?</h2>${nearRoutes.length ? `<div class="dim">You're at ${ST[near.sid].n}:</div><div>${nearRoutes.map(r => `<button class="b" onclick="G.pickRoute('${r}','${near.sid}')">${bullet(r, 1)}</button>`).join('')}</div><div class="dim">or any line:</div>` : `<div class="dim">${Sensors.gpsState === 'asking' ? 'Looking for you…' : 'No station nearby. Pick a train.'}</div>`}
    <div>${Object.keys(DATA.routes).map(r => `<button class="b" onclick="G.pickRoute('${r}')" ${startRoute === r ? 'style="outline:2px solid #fff"' : ''}>${bullet(r, 1)}</button>`).join('')}</div>`;
  if (startRoute) {
    const R = DATA.routes[startRoute];
    if (startIdx === null) {
      h += `<h2>Where are you?</h2><select onchange="G.pickStop(+this.value)"><option>pick your station</option>${R.stops.map((sid, i) => `<option value="${i}">${ST[sid].n}</option>`).join('')}</select>`;
    } else {
      h += `<h2>${ST[R.stops[startIdx]].n}. Which way?</h2>
        ${startIdx < R.stops.length - 1 ? `<button class="go" onclick="G.go(1)">toward ${ST[R.stops.at(-1)].n}</button>` : ''}
        ${startIdx > 0 ? `<button class="go" onclick="G.go(-1)">toward ${ST[R.stops[0]].n}</button>` : ''}`;
    }
  }
  const runs = JSON.parse(localStorage.getItem('runs') || '[]');
  if (runs.length) h += `<h2>Past rides</h2><div class="log" style="height:auto">${runs.slice(0, 5).map(r => `<div>${r.message}</div>`).join('')}</div>`;
  app.innerHTML = h + mockPanel();
}
function renderEnd() {
  const r = S.result;
  app.innerHTML = `<h1>${r.exited ? '🚶 You exited the system' : '💀 Out of swipes'}</h1>
    <div class="panel">${bullet(r.line, 1)} ${r.legs} stops · ${r.waves} waves · ${r.gold} gold earned<br>${r.exited ? 'Got off at' : 'Wiped near'} ${r.exitedAt}<br>Crew: ${r.crew || 'nobody'}</div>
    <div class="dim">📟 ${FRIDGE_URL ? 'Sent to the fridge.' : 'Fridge not hooked up yet (add ?fridge=url).'}</div>
    <button class="go" onclick="G.reset()">New ride</button>`;
}

// ---------------------------------------------------------------- wiring
window.G = {
  buy, sell, select, reroll,
  depart: () => depart('you said so'),
  arrive: () => arrive(S.fromIdx + S.dir, 'you said so'),
  exit: () => { if (confirm('Exit the system and end this run?')) end(true); },
  pickRoute(r, sid) { startRoute = r; startIdx = sid ? DATA.routes[r].stops.indexOf(sid) : null; render(); },
  pickStop(i) { startIdx = i; render(); },
  go(dir) { newRun(startRoute, startIdx, dir); if (MOCK) { Mock.autoAt = now(); mockGps(S.stops[S.idx]); } },
  reset() { S = null; startRoute = startIdx = null; save(); render(); },
  mockNet, mockGps: sid => mockGps(sid || null), mockAuto(on) { Mock.auto = on; Mock.autoAt = now(); render(); }, mockSpeed(x) { Mock.speed = x; render(); },
};
Sensors.start();
if (S && S.phase === 'riding' && S.fight) S.fight.lastTick = Math.min(S.fight.lastTick, now()); // catch up on reload
render();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
