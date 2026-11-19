const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const web = path.resolve(process.argv[2]);
const report = path.resolve(process.argv[3]);
const mode = process.argv[4] || 'game';
const mime = {html:'text/html',js:'text/javascript',wasm:'application/wasm',pck:'application/octet-stream',png:'image/png'};
fs.mkdirSync(report, {recursive:true});

const server = http.createServer((request, response) => {
  const endpoint = new URL(request.url, 'http://localhost').pathname;
  const file = path.join(web, endpoint === '/' ? 'index.html' : endpoint);
  if (!file.startsWith(web + path.sep) || !fs.existsSync(file)) {
    response.writeHead(404);
    response.end();
    return;
  }
  response.setHeader('Content-Type', mime[path.extname(file).slice(1)] || 'application/octet-stream');
  if (endpoint === '/' && mode === 'game') {
    const withBenchmark = fs.readFileSync(file, 'utf8').replace('"args":[]','"args":["--","--benchmark"]');
    response.setHeader('Content-Length', Buffer.byteLength(withBenchmark));
    response.end(withBenchmark);
    return;
  }
  response.setHeader('Content-Length', fs.statSync(file).size);
  fs.createReadStream(file).pipe(response);
});

async function waitUntil(check, desc, page, timeout = 45000) {
  const until = Date.now() + timeout;
  for (let result; !(result = check());) {
    if (Date.now() > until) throw new Error(`Timed out: ${desc}`);
    await page.waitForTimeout(100);
  }
  return check();
}

async function main() {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const rows = [];
  const errors = [];
  const profiles = [];
  const metrics = [];
  const assets = {};
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'velocity-chromium-'));
  let context;
  const url = `http://127.0.0.1:${server.address().port}/`;
  const boot = async (width, height) => {
    context = await chromium.launchPersistentContext(profileDir, {
      executablePath: process.env.WEB_TEST_BROWSER || '/usr/bin/chromium',
      args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
      ignoreDefaultArgs:['--mute-audio'],
      viewport:{width,height},
      deviceScaleFactor:1,
      hasTouch:true,
    });
    await context.addInitScript(() => {
      const Original = window.AudioContext;
      window.velocityAudio = [];
      if (Original) {
        window.AudioContext = class extends Original {
          constructor(...args) {
            super(...args);
            window.velocityAudio.push(this);
          }
        };
      }
    });
    const page = context.pages()[0] || await context.newPage();
    page.on('console', (message) => {
      const line = message.text();
      rows.push(`${message.type()}: ${line}`);
      if (message.type() === 'error') errors.push(line);
      if (line.startsWith('VELOCITY_PERF ')) metrics.push(JSON.parse(line.slice(14)));
      if (line.startsWith('VELOCITY_PROFILE ')) profiles.push(JSON.parse(line.slice(17)));
    });
    page.on('pageerror', (error) => errors.push(String(error)));
    page.on('response', (response) => {
      const parsed = new URL(response.url());
      assets[parsed.pathname] = response.status();
    });
    await page.goto(url, {waitUntil:'domcontentloaded'});
    return page;
  };
  try {
    let page = await boot(1280,800);
    const ready = mode === 'probe' ? 'VELOCITY_GODOT_WEB_PROBE_READY' : 'VELOCITY_GAME_READY';
    await waitUntil(() => rows.some((row) => row.includes(ready)), ready, page);
    await page.locator('canvas').click({position:{x:646,y:519}});
    const audio = await page.evaluate(() => window.velocityAudio.map((item) => item.state));
    if (mode === 'game') {
      const state = await waitUntil(() => profiles[0], 'initial profile', page);
      assert.equal(state.stage, '0');
      assert.equal(state.persistent, true);
      await page.screenshot({path:path.join(report,'calder-desktop.png')});
      await page.keyboard.down('w');
      await page.keyboard.down('Shift');
      await page.waitForTimeout(4600);
      await page.keyboard.up('Shift');
      await page.keyboard.up('w');
      await page.screenshot({path:path.join(report,'street-desktop.png')});
      const played = await waitUntil(() => profiles.find((item) => item.stage === '1' && item.credits > 0),'movement earns SFC and advances the first objective',page);
      await waitUntil(() => metrics.find((item) => item.quality===1 && !item.paused), 'medium benchmark',page);
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
      await page.screenshot({path:path.join(report,'operations-desktop.png')});
      // Actual canvas controls. Settings opens from Escape on this HUD.
      for (let count=0;count<3;count++) {
        await page.mouse.click(1035,287);
        await page.waitForTimeout(240);
      }
      await page.keyboard.press('Escape');
      const low = await waitUntil(() => metrics.find((item) => item.quality===0 && !item.paused), 'low benchmark',page);
      assert.ok(low.fps > 0 && low.p95_ms > 0 && low.world.resident <= low.world.cap);
      await page.screenshot({path:path.join(report,'calder-low.png')});
      const indexedDb = await page.evaluate(async () => (await indexedDB.databases()).map(({name,version}) => ({name,version})));
      assert.ok(indexedDb.some((database) => database.name === '/userfs'));
      await context.close();
      context = undefined;
      const known = profiles.length;
      page = await boot(1152,648);
      const recovered = await waitUntil(() => profiles[known], 'profile on a new Chromium process',page);
      assert.equal(recovered.stage, played.stage);
      assert.equal(recovered.quality, 0);
      assert.ok(recovered.credits >= played.credits);
      await page.screenshot({path:path.join(report,'landscape-16x9.png')});
      console.log(JSON.stringify({audio,indexedDb,played,recovered,metrics}));
    }
    for (const asset of ['/','/index.js','/index.wasm','/index.pck']) assert.equal(assets[asset], 200);
    assert.deepEqual(errors.filter((message) => !message.includes('favicon.ico')), []);
    console.log(`PASS ${mode} browser HTTP and Godot renderer`);
  } finally {
    fs.writeFileSync(path.join(report, 'browser.json'), JSON.stringify({rows,errors,assets,profiles,metrics},null,2));
    if (context) await context.close();
    fs.rmSync(profileDir, {recursive:true,force:true});
  }
}

main().catch((error) => {console.error(error);process.exitCode = 1;}).finally(() => server.close());
