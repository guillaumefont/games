// Captures the Google Play store graphics from the real game (web/index.html) in headless Chromium:
//   node perigee/tools/store_assets.cjs        (needs the playwright package and its Chromium)
// Writes perigee/store/: screenshot-1-start.png, screenshot-2-orbit.png, screenshot-3-flight.png,
// screenshot-4-over.png (1080x1920 phone screenshots) and feature-graphic.png (1024x500).
// The icon for the listing is web/icon.png (512x512, from tools/make_icons.py).
const path = require('path');
const { chromium } = require('playwright');

const WEB = path.resolve(__dirname, '../web');
const OUT = path.resolve(__dirname, '../store');
const PAGE = 'file://' + path.join(WEB, 'index.html');

// Same bot as tests/play_test.cjs: fling toward the nearest unvisited moon, hold while crossing its ring.
function installBot() {
  const G = window.perigeeTest;
  const key = (type) => window.dispatchEvent(new KeyboardEvent(type, { code: 'Space', bubbles: true }));
  let down = false, orbitSince = 0;
  window.bot = { on: true };
  function tick() {
    if (!window.bot.on) return;
    const p = G.player;
    if (G.state !== 'play') return requestAnimationFrame(tick);
    if (p.planet) {
      if (down) { key('keyup'); down = false; orbitSince = performance.now(); }
      if (!orbitSince) orbitSince = performance.now();
      const dist = q => Math.hypot(q.x - p.planet.x, q.y - p.planet.y);
      const target = G.planets.filter(q => !q.visited).sort((a, b) => dist(a) - dist(b))[0];
      if (target && performance.now() - orbitSince > 250) {
        const c = Math.cos(p.ang), s = Math.sin(p.ang);
        const vx = p.vr * c - s * p.dir * p.vt, vy = p.vr * s + c * p.dir * p.vt;
        const tx = target.x - p.x, ty = target.y - p.y;
        if (Math.abs(Math.atan2(vx * ty - vy * tx, vx * tx + vy * ty)) < 0.1) { key('keydown'); key('keyup'); }
      }
    } else {
      const inRing = G.planets.some(q => !q.visited && Math.hypot(q.x - p.x, q.y - p.y) < q.ring);
      if (inRing && !down) { key('keydown'); down = true; }
      else if (!inRing && down) { key('keyup'); down = false; }
    }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

(async () => {
  const launchOpts = process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {};
  const browser = await chromium.launch(launchOpts);
  const page = await browser.newPage({ viewport: { width: 360, height: 640 }, deviceScaleFactor: 3 });
  await page.goto(PAGE);
  await page.evaluate(() => { try { localStorage.setItem('perigee-best', '27'); } catch (e) {} });
  await page.reload();
  await page.waitForFunction(() => window.perigeeTest && window.perigeeTest.state === 'start');
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(OUT, 'screenshot-1-start.png') });

  await page.keyboard.down('Space'); await page.keyboard.up('Space');
  await page.evaluate(installBot);
  // orbiting a moon a few hops in (the tutorial hint is gone after 3 moons)
  await page.waitForFunction(() => { const G = window.perigeeTest; return G.state === 'over' || (G.hops >= 4 && !!G.player.planet); }, null, { timeout: 90000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(OUT, 'screenshot-2-orbit.png') });
  // in flight, holding inside the next moon's ring, with sparks around
  await page.waitForFunction(() => { const G = window.perigeeTest; return G.state === 'over' || (G.hops >= 7 && G.holding && !G.player.planet); }, null, { timeout: 90000 });
  await page.screenshot({ path: path.join(OUT, 'screenshot-3-flight.png') });
  // a new best: let the bot go past 27 if it can, then drift off
  await page.waitForFunction(() => window.perigeeTest.score >= 30 || window.perigeeTest.state === 'over', null, { timeout: 120000 });
  await page.evaluate(() => { window.bot.on = false; window.dispatchEvent(new KeyboardEvent('keyup', { code: 'Space' })); });
  await page.waitForTimeout(300);
  if (await page.evaluate(() => !!window.perigeeTest.player.planet)) { await page.keyboard.down('Space'); await page.keyboard.up('Space'); }
  await page.waitForSelector('#over:not([hidden])', { timeout: 20000 });
  await page.waitForTimeout(400);
  await page.screenshot({ path: path.join(OUT, 'screenshot-4-over.png') });
  const score = await page.evaluate(() => window.perigeeTest.score);
  console.log('run score', score);

  // Feature graphic: the title beside a live frame of the game.
  const shot = 'data:image/png;base64,' + (await page.screenshot({ type: 'png' })).toString('base64');
  await page.close();
  const fg = await browser.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 1 });
  const orbit = 'data:image/png;base64,' + require('fs').readFileSync(path.join(OUT, 'screenshot-3-flight.png')).toString('base64');
  // fonts inlined: a page set from a string can't load file:// stylesheets
  const font = (fam, w, f) => `@font-face{font-family:"${fam}";font-weight:${w};src:url(data:font/woff2;base64,${
    require('fs').readFileSync(path.join(WEB, 'fonts', f)).toString('base64')}) format("woff2");}`;
  const fonts = font('Unbounded', 800, 'unbounded-latin-800-normal.woff2') + font('Manrope', 700, 'manrope-latin-700-normal.woff2');
  await fg.setContent(`<!doctype html><html><head><style>${fonts}
    body{margin:0;width:1024px;height:500px;overflow:hidden;background:linear-gradient(#141634,#1d2150);color:#f3ecdf;font-family:Manrope,sans-serif;position:relative}
    .t{position:absolute;left:72px;top:150px;font:800 92px/1 Unbounded,sans-serif;letter-spacing:-.02em}
    .t span{color:#ff8a6b}
    .s{position:absolute;left:76px;top:268px;font:700 26px/1.35 Manrope,sans-serif;color:#9aa0cf;max-width:460px}
    .phone{position:absolute;right:70px;top:-60px;width:360px;height:640px;border-radius:36px;overflow:hidden;transform:rotate(8deg);box-shadow:0 30px 80px rgba(0,0,0,.5);border:6px solid #2a2f6a}
    .phone img{width:100%;height:100%;display:block;object-fit:cover}
  </style></head><body><div class="t">Peri<span>gee</span></div><div class="s">One finger. Endless moons.<br>Don't drift into the dark.</div>
  <div class="phone"><img src="${orbit}"></div></body></html>`);
  await fg.evaluate(() => document.fonts.ready);
  await fg.waitForTimeout(300);
  await fg.screenshot({ path: path.join(OUT, 'feature-graphic.png') });
  await browser.close();
  console.log('store graphics written to', OUT);
})().catch(e => { console.error(e); process.exit(1); });
