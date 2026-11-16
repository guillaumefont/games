// Headless play test for Perigee (web/index.html), run in Chromium with Playwright:
//   node perigee/tests/play_test.cjs
// Checks that the page loads offline with no script errors and its bundled fonts, that a simple
// bot can hop from moon to moon and score, that drifting off ends the run with the game-over card,
// that the best score is kept, and that tapping again starts a fresh run. Then, with a fake of the
// Android shell's window.PerigeeAndroid, checks the remove-ads, privacy and continue buttons.
// The bot reads the game through window.perigeeTest (read-only) and plays with the Space key,
// exactly like a player: tap to fling, hold while crossing a ring to get caught.
// The last line printed on success is "PLAY TEST DONE"; CI checks for it.
const path = require('path');
const { chromium } = require('playwright');

const PAGE = 'file://' + path.resolve(__dirname, '../web/index.html');
let failures = 0;
function check(ok, what) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`);
  if (!ok) failures++;
}

(async () => {
  const launchOpts = process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {};
  const browser = await chromium.launch(launchOpts);
  const page = await browser.newPage({ viewport: { width: 412, height: 860 } });
  const errors = [], external = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('request', r => { if (!r.url().startsWith('file:') && !r.url().startsWith('data:')) external.push(r.url()); });

  await page.goto(PAGE);
  await page.waitForFunction(() => window.perigeeTest && window.perigeeTest.state === 'start');
  await page.evaluate(() => document.fonts.ready);
  check(await page.evaluate(() => document.fonts.check('800 40px Unbounded') && document.fonts.check('700 15px Manrope')),
    'bundled fonts (Unbounded, Manrope) load');
  check(await page.isVisible('#start'), 'start card is shown');

  // The bot runs inside the page so it reacts every frame.
  await page.evaluate(() => {
    const G = window.perigeeTest;
    const key = (type) => window.dispatchEvent(new KeyboardEvent(type, { code: 'Space', bubbles: true }));
    let down = false, orbitSince = 0;
    window.bot = { on: true };
    function tick() {
      if (!window.bot.on) return;
      const p = G.player;
      if (G.state !== 'play') return requestAnimationFrame(tick);
      if (p.planet) {
        // Just caught: let go at once (a release within 0.15 s of a capture does not fling).
        if (down) { key('keyup'); down = false; orbitSince = performance.now(); }
        if (!orbitSince) orbitSince = performance.now();
        // Fling when the ship's heading points at the nearest unvisited moon.
        const dist = q => Math.hypot(q.x - p.planet.x, q.y - p.planet.y);
        const target = G.planets.filter(q => !q.visited).sort((a, b) => dist(a) - dist(b))[0];
        if (target && performance.now() - orbitSince > 250) {
          const c = Math.cos(p.ang), s = Math.sin(p.ang);
          const vx = p.vr * c - s * p.dir * p.vt, vy = p.vr * s + c * p.dir * p.vt;
          const tx = target.x - p.x, ty = target.y - p.y;
          const diff = Math.abs(Math.atan2(vx * ty - vy * tx, vx * tx + vy * ty));
          if (diff < 0.1) { key('keydown'); key('keyup'); }
        }
      } else {
        // In flight: hold only while crossing the ring of a moon not visited yet.
        const inRing = G.planets.some(q => !q.visited && Math.hypot(q.x - p.x, q.y - p.y) < q.ring);
        if (inRing && !down) { key('keydown'); down = true; }
        else if (!inRing && down) { key('keyup'); down = false; }
      }
      requestAnimationFrame(tick);
    }
    window.bot.start = () => requestAnimationFrame(tick);
  });

  // Start: the first tap only closes the start card.
  await page.keyboard.down('Space'); await page.keyboard.up('Space');
  check(await page.evaluate(() => window.perigeeTest.state === 'play'), 'tap starts the game');
  check(await page.isHidden('#start'), 'start card hides');

  await page.evaluate(() => window.bot.start());
  await page.waitForFunction(() => window.perigeeTest.score >= 6 || window.perigeeTest.state === 'over', null, { timeout: 90000 })
    .catch(async e => {
      console.log('bot stuck:', JSON.stringify(await page.evaluate(() => {
        const G = window.perigeeTest, p = G.player;
        return { score: G.score, hops: G.hops, state: G.state, on: p.planet && p.planet.k, ang: p.ang, r: p.r,
          planets: G.planets.map(q => ({ k: q.k, x: Math.round(q.x), y: Math.round(q.y), v: q.visited, ring: Math.round(q.ring) })) };
      })));
      throw e;
    });
  const run1 = await page.evaluate(() => ({ score: window.perigeeTest.score, hops: window.perigeeTest.hops, state: window.perigeeTest.state }));
  console.log(`bot run: score ${run1.score}, moons ${run1.hops}, state ${run1.state}`);
  check(run1.hops >= 3, 'the bot hops at least 3 moons');
  check(+(await page.textContent('#score')) === run1.score, 'HUD shows the score');

  // Stop the bot and let go: the ship flings off and drifts into the dark.
  await page.evaluate(() => {
    window.bot.on = false;
    const key = (type) => window.dispatchEvent(new KeyboardEvent(type, { code: 'Space' }));
    key('keyup');
  });
  await page.waitForTimeout(300); // past the 0.15 s capture lock-out
  if (await page.evaluate(() => !!window.perigeeTest.player.planet)) { await page.keyboard.down('Space'); await page.keyboard.up('Space'); }
  await page.waitForFunction(() => window.perigeeTest.state === 'over', null, { timeout: 20000 });
  await page.waitForSelector('#over:not([hidden])', { timeout: 5000 });
  const why = await page.textContent('#overWhy');
  check(/dark|moon/i.test(why), `game over card says why ("${why}")`);
  const final = await page.evaluate(() => window.perigeeTest.score);
  check(+(await page.textContent('#overScore')) === final, 'game over card shows the score');
  check(await page.evaluate(() => +localStorage.getItem('perigee-best')) === final, 'best score is saved');

  // Tap again (after the short lock-out) to fly again from zero.
  await page.waitForTimeout(600);
  await page.keyboard.down('Space'); await page.keyboard.up('Space');
  check(await page.evaluate(() => window.perigeeTest.state === 'play' && window.perigeeTest.score === 0), 'tap restarts from zero');
  check(await page.isHidden('#over'), 'game over card hides');
  check((await page.textContent('#best')) === `Best ${final}`, 'HUD keeps the best score');

  await page.screenshot({ path: process.env.SHOT || path.join(require('os').tmpdir(), 'perigee.png') });
  check(await page.isHidden('#cont') && await page.isHidden('#buyStart'), 'the browser build shows no continue or purchase buttons');

  // Android app: the shell's window.PerigeeAndroid is faked here to check the page's side of it.
  const app = await browser.newPage({ viewport: { width: 412, height: 860 } });
  app.on('pageerror', e => errors.push(String(e)));
  app.on('request', r => { if (!r.url().startsWith('file:') && !r.url().startsWith('data:')) external.push(r.url()); });
  await app.addInitScript(() => {
    window.calls = [];
    window.PerigeeAndroid = {};
    for (const fn of ['runStart', 'runEnd', 'restart', 'continueRun', 'buyRemoveAds', 'privacy'])
      window.PerigeeAndroid[fn] = (...a) => window.calls.push([fn, ...a]);
    window.PerigeeAndroid.state = () => JSON.stringify({ adsRemoved: false, canContinue: true, price: '$1.99' });
  });
  await app.goto(PAGE);
  await app.waitForFunction(() => window.perigeeTest && window.perigeeTest.state === 'start');
  check((await app.textContent('#buyStart')).includes('$1.99') && await app.isVisible('#buyStart'), 'app: start card offers "Remove ads" with its price');
  await app.click('#privacy');
  await app.click('#buyStart');
  check(await app.evaluate(() => window.perigeeTest.state === 'start'), 'app: the buttons do not start the game');
  await app.keyboard.down('Space'); await app.keyboard.up('Space');
  // fling off without holding: the run ends
  await app.waitForTimeout(300);
  await app.keyboard.down('Space'); await app.keyboard.up('Space');
  await app.waitForFunction(() => window.perigeeTest.state === 'over', null, { timeout: 20000 });
  await app.waitForSelector('#cont:not([hidden])', { timeout: 5000 });
  check((await app.textContent('#cont')) === 'Watch an ad to continue', 'app: game over offers a continue');
  await app.click('#cont');
  await app.evaluate(() => window.perigeeNative.onEvent('continue', { ok: true })); // the ad was watched
  const revived = await app.evaluate(() => ({ s: window.perigeeTest.state, c: window.perigeeTest.continued, on: !!window.perigeeTest.player.planet }));
  check(revived.s === 'play' && revived.c && revived.on, 'app: a rewarded continue puts the ship back in orbit');
  check(await app.isHidden('#over'), 'app: the game over card hides on continue');
  await app.waitForTimeout(300);
  await app.keyboard.down('Space'); await app.keyboard.up('Space');
  await app.waitForFunction(() => window.perigeeTest.state === 'over', null, { timeout: 20000 });
  await app.waitForSelector('#over:not([hidden])', { timeout: 5000 });
  check(await app.isHidden('#cont'), 'app: only one continue per run');
  await app.waitForTimeout(600);
  await app.keyboard.down('Space'); await app.keyboard.up('Space');
  const calls = (await app.evaluate(() => window.calls)).map(c => c[0]);
  console.log('app calls:', calls.join(' '));
  check(['privacy', 'buyRemoveAds', 'runStart', 'runEnd', 'continueRun', 'restart'].every(c => calls.includes(c)),
    'app: the page calls the shell for privacy, purchase, continue, restart and analytics');
  check(calls.filter(c => c === 'runEnd').length === 2, 'app: each death is reported once');

  check(errors.length === 0, 'no script errors' + (errors.length ? ': ' + errors.join(' | ') : ''));
  check(external.length === 0, 'no network requests (works offline)' + (external.length ? ': ' + external.join(' ') : ''));
  await browser.close();
  if (failures) { console.log(`${failures} check(s) failed`); process.exit(1); }
  console.log('PLAY TEST DONE');
})().catch(e => { console.error(e); process.exit(1); });
