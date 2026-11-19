'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { PNG } = require('pngjs');
const { chromium } = require('playwright');

const webRoot = path.resolve(process.argv[2]);
const reportRoot = path.resolve(process.argv[3]);
const mime = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
};
const server = http.createServer((request, response) => {
  const endpoint = new URL(request.url, 'http://localhost').pathname;
  const filename = path.resolve(webRoot, endpoint === '/' ? 'index.html' : endpoint.slice(1));
  if (!filename.startsWith(webRoot + path.sep) || !fs.existsSync(filename)) {
    response.writeHead(404).end();
    return;
  }
  response.setHeader('Content-Type', mime[path.extname(filename)] || 'application/octet-stream');
  fs.createReadStream(filename).pipe(response);
});

function amber(image, fromX, fromY, width, height) {
  let count = 0;
  for (let y = fromY; y < fromY + height; y += 1) {
    for (let x = fromX; x < fromX + width; x += 1) {
      const offset = (y * image.width + x) * 4;
      const [r, g, b] = image.data.subarray(offset, offset + 3);
      if (r > 248 && g >= 184 && g < 201 && b >= 112 && b < 130) count++;
    }
  }
  return count;
}

function pictureDistance(previous, next, left, top, width, height) {
  let total = 0;
  for (let y = top; y < top + height; y += 4) {
    for (let x = left; x < left + width; x += 4) {
      const offset = (y * previous.width + x) * 4;
      for (let c = 0; c < 3; c += 1) total += Math.abs(previous.data[offset + c] - next.data[offset + c]);
    }
  }
  return total / (Math.ceil(width / 4) * Math.ceil(height / 4) * 3);
}

function joystickOutline(image, centerX, centerY) {
  let count = 0;
  for (let y = centerY - 22; y <= centerY + 22; y += 1) {
    for (let x = centerX - 22; x <= centerX + 22; x += 1) {
      const offset = (y * image.width + x) * 4;
      const [r, g, b] = image.data.subarray(offset, offset + 3);
      if (r >= 146 && r <= 218 && g > r + 11 && b > g + 3) count++;
    }
  }
  return count;
}

async function main() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({
    executablePath: process.env.WEB_TEST_BROWSER || '/usr/bin/chromium',
    args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  try {
    const context = await browser.newContext({
      viewport: {width: 1280, height: 800}, isMobile: true, hasTouch: true, deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    const device = await context.newCDPSession(page);
    const errors = [];
    let boots = 0;
    page.on('console', message => {
      if (message.text().includes('VELOCITY_GAME_READY')) boots++;
      if (message.type() === 'error' && !message.text().includes('status of 404')) errors.push(message.text());
    });
    page.on('pageerror', error => errors.push(error.message));
    fs.mkdirSync(reportRoot, {recursive: true});
    const capture = async name => PNG.sync.read(await page.screenshot({path: path.join(reportRoot, name + '.png')}));
    const waitBoot = async count => {
      const deadline = Date.now() + 45000;
      while (boots < count && Date.now() < deadline) await page.waitForTimeout(200);
      assert.equal(boots, count, 'Godot signals startup');
      await page.waitForTimeout(450);
    };
    const touch = (type, touchPoints) => device.send('Input.dispatchTouchEvent', {type, touchPoints});
    const point = (id, x, y) => ({id, x, y, radiusX: 9, radiusY: 9, force: 1});
    const tap = async (x, y) => {
      await touch('touchStart', [point(0, x, y)]);
      await page.waitForTimeout(50);
      await touch('touchEnd', []);
      await page.waitForTimeout(300);
    };

    await page.goto(`http://127.0.0.1:${server.address().port}/`, {waitUntil: 'domcontentloaded'});
    await waitBoot(1);
    await tap(800, 325);
    const before = await capture('touch-hud-16x10');
    const move = point(10, 102, 659);
    const look = point(11, 833, 398);
    const boost = point(12, 1217, 595);
    const jump = point(13, 1147, 595);
    await touch('touchStart', [move, look, boost, jump]);
    await touch('touchMove', [move, point(11, 925, 420), boost, jump]);
    await page.waitForTimeout(380);
    const running = await capture('touch-move-look-jump-boost');
    assert(pictureDistance(before, running, 325, 250, 570, 370) > 18,
      'Simultaneous physical pointer events change the rendered chase view');
    await touch('touchCancel', []);
    await page.waitForTimeout(420);

    await tap(1106, 751);
    const limited = await capture('touch-limiter');
    assert(amber(limited, 1100, 745, 12, 5) >= 22, 'Touch moves the visible limiter knob to its new location');

    await tap(1223, 51);
    await tap(270, 534);
    await capture('touch-layout-settings');
    await tap(1040, 261);
    await capture('touch-layout-editor');
    const editedJoystick = point(0, 290, 612);
    await touch('touchStart', [point(0, 102, 702)]);
    await touch('touchMove', [editedJoystick]);
    await touch('touchEnd', []);
    await tap(800, 109);
    const edited = await capture('touch-layout-edited');
    assert(joystickOutline(edited, 290, 612) >= 100, 'Dragging the editor moves the rendered movement joystick');

    await page.waitForTimeout(950);
    await page.reload({waitUntil: 'domcontentloaded'});
    await waitBoot(2);
    const reloaded = await capture('touch-reload');
    assert(amber(reloaded, 1100, 745, 12, 5) >= 22, 'Reload restores the limiter from Web storage');
    assert(joystickOutline(reloaded, 290, 612) >= 100, 'Reload restores the edited control from Web storage');

    await page.setViewportSize({width: 1280, height: 720});
    await page.waitForTimeout(600);
    const wide = await capture('touch-hud-16x9');
    assert.equal(wide.width / wide.height, 16 / 9, 'The browser runs at 16:9');
    for (const x of [6, wide.width - 7]) {
      let brightness = 0;
      for (let y = 210; y < 510; y += 4) {
        brightness += wide.data[(y * wide.width + x) * 4];
      }
      assert(brightness / 75 > 18, 'The game fills the expanded landscape viewport without pillarboxing');
    }
    assert.deepEqual(errors, [], 'The exported game produces no runtime errors');
    console.log(JSON.stringify({boots, width: wide.width, height: wide.height, device: 'Chromium emulated touchscreen'}));
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => server.close());
