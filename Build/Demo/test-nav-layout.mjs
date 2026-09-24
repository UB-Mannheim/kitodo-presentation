#!/usr/bin/env node
// Regression test for the aurora demo theme's kiosk-fullscreen layout.
//
// Two guards, both rendered against the real aurora.css + demo-widgets.css in
// a headless browser:
//
//  1. The nav row (first / prev / page-select / next / last / double-page)
//     lives in a 16em sidebar and must stay on a single row. The page selector
//     is a native <select> that sizes itself to its WIDEST option, so a
//     document whose page labels are long (a periodical's "[22] - 18") can
//     make the page pill wider than the sidebar and push the trailing buttons
//     onto a second row. This test renders several label shapes and asserts
//     the row does not wrap.
//
//  2. The demo's fixed style-selector widget (.dlf-demo-styles, top-right)
//     must not cover the fullscreen navigation or toolbox. It was once moved
//     down to a gap between the two and ended up hiding parts of the toolbox;
//     it now keeps its normal top position and the nav is pushed below it, so
//     the widget only ever overlaps empty space. This test measures the
//     widget against both frames and asserts they do not intersect.
//
// No framework: it drives the system Chrome (the same one used for viewer
// debugging, see AGENTS.md) and reads the measured geometry back out of the
// emitted DOM. Run it before committing changes to the demo themes:
//
//   node Build/Demo/test-nav-layout.mjs      (or: npm run -C Build test:layout)
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

let CHROME = process.env.CHROME
  || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// A label set per case. `count` page options are generated; `label(i)` is the
// displayed text of option i (1-based).
const CASES = [
  {name: 'short (1..27)', count: 27, label: (i) => String(i)},
  {name: 'three-digit (1..300)', count: 300, label: (i) => String(i)},
  // A periodical: long "[a] - b" labels are the documented failure shape.
  {name: 'periodical labels', count: 27, label: (i) => `[${i}] - ${i > 4 ? i - 4 : i}`},
];

// Vertical offset (relative to the nav frame) at which an item counts as "on
// the next row". The items are ~32-46px tall and vertically centered on one
// row, so same-row tops differ by only a few px; a wrapped row sits ~40px
// lower. 20px sits comfortably between the two.
const WRAP_TOLERANCE_PX = 20;

// The demo's style-selector widget, with markup mirroring setup-demo.sh (a
// label, the style <select> and the dark-mode toggle). It is position:fixed
// top-right via demo-widgets.css.
const STYLE_WIDGET = `<div class="dlf-demo-styles"><label for="dlf-demo-style">Style</label><select id="dlf-demo-style" data-base="kitodo-demo/"><option value="aurora/aurora.css">aurora</option><option value="bar/bar.css">bar</option></select><label for="dlf-demo-dark"><input type="checkbox" id="dlf-demo-dark">Dark</label></div>`;

// The fullscreen toolbox frame: a <ul> of the tools that fullscreen shows
// (zoom, fullscreen, fulltext). The fulltext <li> carries an id^="tx-dlf-tools-",
// which is what demo-widgets.css uses to identify the toolbox frame.
const TOOLBOX_FRAME = `<div class="frame"><ul>
    <li class="tx-dlf-tools-zoom-in"><a href="#" title="Zoom In">Zoom In</a></li>
    <li class="tx-dlf-tools-fullscreen"><a href="#" title="Fullscreen Mode">Fullscreen Mode</a></li>
    <li class="tx-dlf-tools-fulltext"><a href="#" id="tx-dlf-tools-fulltext" title="Fulltext">Fulltext</a></li>
</ul></div>`;

function fixtureFor(name, count, label) {
  const opts = Array.from({length: count}, (_, k) =>
    `<option value="${k + 1}">${label(k + 1)}</option>`).join('');
  // The real demo-widgets.css + aurora.css are loaded by absolute file:// path,
  // so the test exercises exactly the shipped CSS, not a copy. The demo-widgets
  // fullscreen grid (#main.tx-dlf-fullscreen) already carries the layout the
  // kiosk mode uses, so no extra styling is needed here. The style widget sits
  // outside #main, exactly as the demo page emits it (fixed, top-right).
  return `<!DOCTYPE html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="file://${widgets}">
<link rel="stylesheet" href="file://${aurora}">
<style>#main.tx-dlf-fullscreen{position:static;width:100vw;}</style>
</head><body style="margin:0">
${STYLE_WIDGET}
<div id="main" class="tx-dlf-fullscreen">
  <div class="frame"><div id="tx-dlf-map">map</div></div>
  <div class="frame">
    <div class="tx-dlf-navigation-first"><a title="First Page">First Page</a></div>
    <div class="tx-dlf-navigation-prev"><a title="Previous Page">Previous Page</a></div>
    <li class="tx-dlf-navigation-pages" title="Select page">
      <form><label>Page</label><select>${opts}</select></form>
    </li>
    <div class="tx-dlf-navigation-next"><a title="Next Page">Next Page</a></div>
    <div class="tx-dlf-navigation-last"><a title="Last Page">Last Page</a></div>
    <div class="tx-dlf-navigation-double"><a title="Double Page View">Double Page View</a></div>
  </div>
  ${TOOLBOX_FRAME}
</div>
<script>
window.addEventListener('load', function () {
  setTimeout(function () {
    var nav = document.querySelector('.frame:has(.tx-dlf-navigation-first)');
    var tools = document.querySelector('.frame:has([id^="tx-dlf-tools-"])');
    var sel = document.querySelector('.dlf-demo-styles');
    var nfr = nav.getBoundingClientRect();
    var tfr = tools.getBoundingClientRect();
    var sfr = sel.getBoundingClientRect();
    function box(r) {
      return {top: Math.round(r.top), bottom: Math.round(r.bottom),
              left: Math.round(r.left), right: Math.round(r.right),
              width: Math.round(r.width), height: Math.round(r.height)};
    }
    function intersects(a, b) {
      return a.left < b.right && a.right > b.left &&
             a.top < b.bottom && a.bottom > b.top;
    }
    var items = Array.prototype.map.call(nav.children, function (c) {
      var b = c.getBoundingClientRect();
      return {name: c.className.split(' ')[0].replace('tx-dlf-navigation-', ''),
              top: Math.round(b.top - nfr.top), width: Math.round(b.width)};
    });
    var tops = items.map(function (i) { return i.top; });
    var pill = nav.querySelector('.tx-dlf-navigation-pages');
    var selSel = nav.querySelector('.tx-dlf-navigation-pages select');
    document.body.setAttribute('data-measure', JSON.stringify({
      name: ${JSON.stringify(name)},
      items: items,
      rowSpread: Math.max.apply(null, tops) - Math.min.apply(null, tops),
      pillWidth: Math.round(pill.getBoundingClientRect().width),
      selectWidth: Math.round(selSel.getBoundingClientRect().width),
      selector: box(sfr),
      navFrame: box(nfr),
      toolsFrame: box(tfr),
      selectorOverlapsNav: intersects(sfr, nfr),
      selectorOverlapsTools: intersects(sfr, tfr)
    }));
  }, 300);
});
</script>
</body></html>`;
}

function runChrome(htmlPath) {
  return new Promise((resolve) => {
    const args = [
      '--headless=new', '--disable-gpu', '--no-sandbox',
      '--virtual-time-budget=6000', '--timeout=20000',
      '--dump-dom', `file://${htmlPath}`,
    ];
    const child = spawn(CHROME, args, {stdio: ['ignore', 'pipe', 'pipe']});
    let out = '';
    child.stdout.on('data', (d) => { out += d; });
    child.on('close', () => resolve(out));
    child.on('error', (e) => { console.error(`  chrome spawn error: ${e.message}`); resolve(''); });
  });
}

function parseMeasure(dom) {
  const m = dom.match(/data-measure="([^"]*)"/);
  if (!m) return null;
  try {
    return JSON.parse(m[1].replace(/&quot;/g, '"'));
  } catch {
    return null;
  }
}

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

async function main() {
  const chrome = findChrome();
  if (!chrome) {
    console.log('test:layout: no Chrome/Chromium found — skipped (set $CHROME to run).');
    process.exit(0);
  }
  CHROME = chrome;
  for (const f of [aurora, widgets]) {
    if (!existsSync(f)) { console.error(`missing stylesheet: ${f}`); process.exit(2); }
  }

  const dir = path.join(tmpdir(), `nav-layout-${process.pid}`);
  let failed = false;
  try {
    mkdirSync(dir, {recursive: true});
    for (const c of CASES) {
      const htmlPath = path.join(dir, `${c.name.replace(/\W+/g, '_')}.html`);
      writeFileSync(htmlPath, fixtureFor(c.name, c.count, c.label));
      const dom = await runChrome(htmlPath);
      const r = parseMeasure(dom);
      if (!r) {
        console.error(`FAIL  ${c.name}: could not measure (no data in browser output)`);
        failed = true;
        continue;
      }
      const wrapped = r.rowSpread > WRAP_TOLERANCE_PX;
      const overlap = r.selectorOverlapsNav || r.selectorOverlapsTools;
      console.log(
        `${wrapped || overlap ? 'FAIL' : 'ok'}  ${c.name.padEnd(22)} ` +
        `rowSpread=${r.rowSpread}px  pill=${r.pillWidth}px  select=${r.selectWidth}px`
      );
      if (wrapped) {
        failed = true;
        console.log(`      the nav row wrapped: ${JSON.stringify(r.items)}`);
      }
      if (overlap) {
        failed = true;
        console.log(`      style selector overlaps the layout:`);
        console.log(`        selector: ${JSON.stringify(r.selector)}`);
        if (r.selectorOverlapsNav) {
          console.log(`        nav frame: ${JSON.stringify(r.navFrame)}`);
        }
        if (r.selectorOverlapsTools) {
          console.log(`        toolbox frame: ${JSON.stringify(r.toolsFrame)}`);
        }
      }
    }
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
  console.log(failed ? '\nnav layout: FAILED' : '\nnav layout: all rows fit and the style selector clears the frames');
  process.exit(failed ? 1 : 0);
}

main();
