#!/usr/bin/env node
// Regression test for the page view's map height when *leaving* kiosk
// fullscreen on a page that loaded already in fullscreen.
//
// The kiosk fullscreen state is persisted in sessionStorage and survives a
// reload (that is what keeps the viewer fullscreen across page navigation).
// The map container normally gets its height from the theme CSS, and the
// viewer applies a 57em inline fallback only while it still measures 0px.
//
// The bug: on a page that loads *already* in fullscreen, the fullscreen layout
// CSS (height: 100% !important on the map) already gives it a non-zero height,
// so the init-time fallback is never applied. Leaving fullscreen then strips
// that CSS rule with no inline height behind it, collapsing the map to 0px and
// hiding the page image. The fix re-applies the fallback when leaving
// fullscreen (dlfViewer.ensureMapContainerHeight, called from toggleFullscreen
// on exit).
//
// This test renders the REAL aurora.css + demo-widgets.css and drives the REAL
// PageView.js prototype methods in headless Chrome, replaying the exact
// sequence: the constructor re-applies fullscreen from sessionStorage, the init
// callback runs the fallback (a no-op, because fullscreen gives a height), and
// toggleFullscreen() leaves fullscreen. It then asserts the map is still
// non-zero. No OpenLayers / TYPO3 needed: the height is pure CSS, so a tiny
// dlfUtils/map stand-in suffices.
//
// No framework: drives the system Chrome (same as test-nav-layout.mjs) and
// reads the measured geometry back out of the emitted DOM. Run it before
// committing changes to the viewer or the demo themes:
//
//   node Build/Demo/test-fullscreen-map-height.mjs   (or: npm run -C Build test:fullscreen)
//
// If no Chrome/Chromium is found the test reports and exits 0 (skipped), so it
// can be wired into environments without a browser.

import {spawn} from 'node:child_process';
import {existsSync, mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const aurora = path.join(root, 'Build/Demo/styles/aurora/aurora.css');
const widgets = path.join(root, 'Build/Demo/assets/demo-widgets.css');
const pageView = path.join(root, 'Resources/Public/JavaScript/PageView/PageView.js');

function findChrome() {
  const candidates = [
    process.env.CHROME,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium-browser',
  ];
  return candidates.find((c) => c && existsSync(c));
}

// The viewer needs only the #main grid and its frames; the map frame carries
// #tx-dlf-map, which the theme/demo CSS lays out. Mirrors the structure
// test-nav-layout.mjs uses, so the fullscreen grid produces a real height.
const FIXTURE = `<!DOCTYPE html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="file://${widgets}">
<link rel="stylesheet" href="file://${aurora}">
<script src="file://${pageView}"></script>
</head><body style="margin:0">
<div id="main">
  <div class="frame"><div id="tx-dlf-map"></div></div>
  <div class="frame">
    <div class="tx-dlf-navigation-first"><a title="First Page">First Page</a></div>
    <div class="tx-dlf-navigation-next"><a title="Next Page">Next Page</a></div>
  </div>
  <div class="frame"><ul>
    <li class="tx-dlf-tools-fullscreen"><a href="#" title="Fullscreen Mode">Fullscreen Mode</a></li>
    <li class="tx-dlf-tools-fulltext"><a href="#" id="tx-dlf-tools-fulltext" title="Fulltext">Fulltext</a></li>
  </ul></div>
</div>
<script>
window.addEventListener('load', function () {
  setTimeout(function () {
    // Stand in for the parts of dlfViewer the code under test touches but that
    // need neither OpenLayers nor a document: the map only needs to exist so the
    // guard passes, and updateSize()/refitView() are no-ops here (the height is
    // pure CSS). dlfUtils.hasContent lets refitView() return early, so the
    // OpenLayers global is never referenced.
    window.dlfUtils = {
      hasContent: function (v) { return !!v && v.length > 0; },
    };
    var viewer = Object.create(dlfViewer.prototype);
    viewer.div = 'tx-dlf-map';
    viewer.fullscreenElementId = 'main';
    viewer.map = { updateSize: function () {} };
    viewer.images = [];

    var map = document.getElementById('tx-dlf-map');
    function h() {
      return {
        inline: map.style.cssText,
        computed: Math.round(parseFloat(getComputedStyle(map).height) || 0),
      };
    }

    var out = {};
    // The map in normal (non-fullscreen) mode: the theme sets no height, so it
    // measures 0px. This is the premise the inline fallback relies on.
    out.normal = h();
    // The page loads already in fullscreen (the state was persisted before the
    // reload): the constructor re-applies the class from sessionStorage.
    window.sessionStorage.setItem('dlf-fullscreen', viewer.fullscreenElementId);
    viewer.applyFullscreenState();
    // init callback: apply the fallback while the map still measures for the
    // (now fullscreen) layout. In fullscreen the CSS gives a height, so this is
    // the no-op that means the inline fallback is never set.
    viewer.ensureMapContainerHeight();
    out.fullscreen = h();
    // The user leaves fullscreen. The fix must restore a non-zero height here.
    viewer.toggleFullscreen();
    out.afterLeave = h();

    document.body.setAttribute('data-result', JSON.stringify(out));
  }, 300);
});
</script>
</body></html>`;

function runChrome(htmlPath) {
  return new Promise((resolve) => {
    const args = [
      '--headless=new', '--disable-gpu', '--no-sandbox',
      '--window-size=1280,800',
      '--virtual-time-budget=6000', '--timeout=20000',
      '--dump-dom', `file://${htmlPath}`,
    ];
    const child = spawn(findChrome(), args, {stdio: ['ignore', 'pipe', 'pipe']});
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('close', () => resolve(out));
    child.on('error', (e) => { console.error(`  chrome spawn error: ${e.message}`); resolve(''); });
  });
}

function parseResult(dom) {
  const m = dom.match(/data-result="([^"]*)"/);
  if (!m) return null;
  try {
    return JSON.parse(m[1].replace(/&quot;/g, '"'));
  } catch {
    return null;
  }
}

async function main() {
  if (!findChrome()) {
    console.log('test:fullscreen: no Chrome/Chromium found — skipped (set $CHROME to run).');
    process.exit(0);
  }
  for (const f of [aurora, widgets, pageView]) {
    if (!existsSync(f)) { console.error(`missing file: ${f}`); process.exit(2); }
  }

  const dir = path.join(tmpdir(), `fs-map-height-${process.pid}`);
  let failed = false;
  try {
    mkdirSync(dir, {recursive: true});
    const htmlPath = path.join(dir, 'fullscreen.html');
    writeFileSync(htmlPath, FIXTURE);
    const r = parseResult(await runChrome(htmlPath));
    if (!r) {
      console.error('FAIL  could not measure (no data in browser output)');
      process.exit(1);
    }
    const collapsed = r.afterLeave.computed <= 0;
    console.log(
      `${collapsed ? 'FAIL' : 'ok'}  leaving fullscreen ` +
      `normal=${r.normal.computed}px  fullscreen=${r.fullscreen.computed}px ` +
      `afterLeave=${r.afterLeave.computed}px (inline: ${JSON.stringify(r.afterLeave.inline)})`
    );
    if (r.normal.computed !== 0) {
      // The premise the fallback relies on: the theme does not set a map height,
      // so a fresh (non-fullscreen) map measures 0px. If that changes the test
      // no longer exercises the fallback, so report it rather than pass silently.
      failed = true;
      console.log(`      premise broken: expected a 0px map in normal mode, got ${r.normal.computed}px`);
    }
    if (r.fullscreen.computed <= 0) {
      failed = true;
      console.log(`      premise broken: expected a non-zero map in fullscreen, got ${r.fullscreen.computed}px`);
    }
    if (collapsed) {
      failed = true;
      console.log(`      the map collapsed to 0px after leaving fullscreen; the page image would disappear`);
    }
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
  console.log(failed ? '\nfullscreen map height: FAILED' : '\nfullscreen map height: OK (map keeps its height after leaving fullscreen)');
  process.exit(failed ? 1 : 0);
}

main();
