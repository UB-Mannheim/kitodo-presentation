#!/usr/bin/env bash
#
# Build a runnable Kitodo.Presentation demo site without Docker.
#
# The result is a live TYPO3 13.4 + SQLite site with the dlf extension
# symlinked in, configured so the PageView viewer works end-to-end (page
# image, navigation, page grid, metadata, toolbox). No Apache Solr, no
# index, no theme CSS are required.
#
# Instead of pointing the viewer at a public document (some hosts sit behind
# anti-bot challenges that a plain HTTP client cannot pass, so a pasted URL
# may fail or return HTML), the script installs a small *local* sample
# document -- committed under examples/local-sample/ (a METS file plus three
# placeholder pages, thumbnails, ALTO fulltext and per-page PDFs) -- and
# serves it on its own static HTTP port. The on-page form is
# pre-filled with that document's URL, so the viewer works completely
# offline. A *separate* port for the data also sidesteps the built-in PHP
# server's single-threaded self-reference deadlock: the app fetches the METS
# and (via its proxy) the page images server-side, and pointing them at the
# app's own port would stall it.
#
# The script bakes in the workarounds a fresh install otherwise needs
# (documented in AGENTS.md, "Local (no-Docker) test installation"):
#
#   * composer.json pins the PHP platform to 8.4.99 (Homebrew may ship a PHP
#     newer than the one the dependencies support) and pulls dlf from the
#     local checkout as a symlinked `path` repository, plus a `github`
#     repository for ubl/php-iiif-prezi-reader (its tag is not on Packagist).
#   * `enableContentLengthHeader = 0` in the site TypoScript so the
#     PageView proxy (a non-seekable guzzle stream) is not given a bogus
#     `Content-Length: 0` by cms-frontend's content-length middleware.
#   * `plugin.tx_dlf_metadata.settings.separator` set, because the setting
#     has no default and MetadataController crashes on multivalued metadata
#     when it is null.
#   * FE `cacheHash.requireCacheHashPresenceParameters['tx_dlf[id]']` and
#     `pageNotFoundOnCHashError = 0` so a viewer request carrying `tx_dlf[id]`
#     renders uncached instead of 404ing on the missing cHash.
#   * The viewer map container height is provided by the extension itself
#     (PageView.js falls back to 57em), so no theme CSS is needed.
#
# Usage:
#   Build/Demo/setup-demo.sh [options]
#
# Options:
#   --dir <path>      Where to create the site (default: $HOME/kitodo-demo-site)
#   --port <n>        Frontend dev-server port / base URL (default: 8090, next
#                     free port used if taken)
#   --branch <name>   dlf branch to install (default: current git branch)
#   --user <name>     Backend admin username (default: admin)
#   --password <pw>   Backend admin password (default: demo-Passw0rd!, must
#                     satisfy TYPO3 policy)
#   --style <name>    Viewer theme to use (default: boxes). The available
#                     themes are the subdirectories of Build/Demo/styles/;
#                     each one holds its main stylesheet <name>.css and may
#                     carry further assets (images, scripts, ...). All
#                     themes are copied into the site, and the page carries
#                     a floating selector so the theme can be switched at
#                     runtime. The choice is remembered in localStorage, so
#                     --style is only the default for a first visit (until
#                     the user picks something else).
#   --serve           Start both servers in the foreground after setup
#   --no-sample       Skip the local sample document (the on-page form then
#                     starts empty; paste any METS / IIIF URL)
#   -h, --help        Show this help
#
# The script is idempotent: it can be re-run against an existing site to
# re-sync it with the current checkout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEMO_DIR="${DEMO_DIR:-$HOME/kitodo-demo-site}"
DEMO_PORT="${DEMO_PORT:-8090}"
STYLE="boxes"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null || true)"
BRANCH="${BRANCH:-main}"
ADMIN_USER="admin"
DEFAULT_PASSWORD="demo-Passw0rd!"
# Honour an ADMIN_PASSWORD environment variable, else the built-in default.
# PASSWORD_IS_DEFAULT is cleared if --password is passed explicitly.
if [ -n "${ADMIN_PASSWORD:-}" ]; then
    PASSWORD_IS_DEFAULT=0
else
    ADMIN_PASSWORD="$DEFAULT_PASSWORD"
    PASSWORD_IS_DEFAULT=1
fi
SERVE=0
MAKE_SAMPLE=1

usage() { awk 'NR==1{next} /^set -euo/{exit} {sub(/^# ?/,""); print}' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DEMO_DIR="$2"; shift 2 ;;
        --port) DEMO_PORT="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --user) ADMIN_USER="$2"; shift 2 ;;
        --password) ADMIN_PASSWORD="$2"; PASSWORD_IS_DEFAULT=0; shift 2 ;;
        --style) STYLE="$2"; shift 2 ;;
        --serve) SERVE=1; shift ;;
        --no-sample) MAKE_SAMPLE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- prerequisites -------------------------------------------------------
for tool in php composer git; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not found on PATH."
done

log "Extension checkout: $REPO (branch: $BRANCH)"
log "Demo site directory: $DEMO_DIR"
log "PHP: $(php -v | head -1)"

# --- pick the viewer style -------------------------------------------------
# A style is a directory under Build/Demo/styles/ containing its main
# stylesheet <name>.css; it may carry further assets (images, scripts, ...)
# that are copied alongside it, so a style can grow into a full theme.
# --style names one of those directories; it is preselected in the page's
# floating style selector. All styles are copied into the site so the
# selector can switch between them at runtime.
STYLES_DIR="$SCRIPT_DIR/styles"
[ -d "$STYLES_DIR" ] || die "Styles directory not found: $STYLES_DIR"
STYLE_DIR="$STYLES_DIR/$STYLE"
[ -d "$STYLE_DIR" ] || die "Unknown style '$STYLE'. Available styles: $(find "$STYLES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | tr '\n' ' ')"
[ -f "$STYLE_DIR/$STYLE.css" ] || die "Style directory '$STYLE' does not contain the main stylesheet '$STYLE.css'."
# One <option> per style directory in Build/Demo/styles/; the current one is
# preselected. New styles are picked up automatically.
STYLE_OPTIONS=""
for d in "$STYLES_DIR"/*/; do
    name="$(basename "$d")"
    sel=""
    [ "$name" = "$STYLE" ] && sel=" selected"
    STYLE_OPTIONS="${STYLE_OPTIONS}<option value=\"${name}/${name}.css\"${sel}>${name}</option>"
done
log "Viewer style: $STYLE"

# --- pick free ports -----------------------------------------------------
find_free_port() {
    local start="$1" p
    for ((p = start; p < start + 100; p++)); do
        if ! lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}
PORT="$(find_free_port "$DEMO_PORT")" || die "Could not find a free port at/after $DEMO_PORT."
[ "$PORT" != "$DEMO_PORT" ] && warn "Port $DEMO_PORT is busy, using $PORT."
DATA_PORT="$(find_free_port "$((PORT + 1))")" || die "Could not find a free data port."
BASE_URL="http://127.0.0.1:${PORT}/"
DATA_URL="http://127.0.0.1:${DATA_PORT}"

# --- create the project --------------------------------------------------
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"

mkdir -p public/kitodo-demo
# All styles (each a directory, copied verbatim so any extra theme assets
# come along) and the widget CSS are copied; the page's floating selector
# references them by <style>/<style>.css. The --style option only decides
# which one is preselected. (No trailing slash on the glob, so the style
# *directories* are copied, not their contents.)
cp -R "$STYLES_DIR"/* "$SCRIPT_DIR/assets/"*.css public/kitodo-demo/

log "Writing composer.json"
cat > composer.json <<JSON
{
    "name": "stweil/kitodo-demo-site",
    "description": "Demo site for Kitodo.Presentation (no Docker), built by Build/Demo/setup-demo.sh",
    "type": "project",
    "license": "GPL-3.0-or-later",
    "require": {
        "typo3/cms-core": "^13.4",
        "typo3/cms-backend": "^13.4",
        "typo3/cms-frontend": "^13.4",
        "typo3/cms-fluid-styled-content": "^13.4",
        "typo3/cms-belog": "^13.4",
        "typo3/cms-install": "^13.4",
        "typo3/cms-fluid": "^13.4",
        "kitodo/presentation": "dev-${BRANCH}"
    },
    "repositories": [
        {
            "type": "path",
            "url": "${REPO}",
            "options": { "symlink": true }
        },
        {
            "type": "github",
            "url": "https://github.com/kitodo/php-iiif-prezi-reader.git"
        }
    ],
    "minimum-stability": "dev",
    "prefer-stable": true,
    "config": {
        "platform": { "php": "8.4.99" },
        "preferred-install": "source",
        "allow-plugins": {
            "typo3/class-alias-loader": true,
            "typo3/cms-composer-installers": true
        }
    },
    "extra": { "typo3/cms": { "web-dir": "public" } }
}
JSON

log "composer install (this can take a while the first time)"
composer install --no-interaction --no-progress

# --- local sample document -----------------------------------------------
# A self-contained sample (METS + 3 placeholder pages, thumbnails, ALTO
# fulltext and per-page PDFs) committed under examples/local-sample/. The METS
# uses absolute FLocat URLs, so rewrite its __DATA_BASE__ placeholder to the
# data server's base URL and drop the files where the data server serves them
# ($DEMO_DIR/kitodo-demo on $DATA_PORT).
if [ "$MAKE_SAMPLE" = "1" ]; then
    log "Installing the local sample documents (examples/)"
    mkdir -p "$DEMO_DIR/kitodo-demo"
    # The image sample is installed at the top level of the data root.
    cp "$SCRIPT_DIR/examples/local-sample/"* "$DEMO_DIR/kitodo-demo/"
    sed -i.bak "s|__DATA_BASE__|${DATA_URL}|g" "$DEMO_DIR/kitodo-demo/sample_mets.xml" && rm -f "$DEMO_DIR/kitodo-demo/sample_mets.xml.bak"
    SAMPLE_URL="${DATA_URL}/sample_mets.xml"
    # The audio / video / 3D samples each live in their own subdirectory (so
    # they can share file names like sample.mp4 / poster.jpg) and their METS
    # files use the same __DATA_BASE__ placeholder, resolved to the sample's
    # own subdirectory.
    AV3D_SOURCES=()
    AV3D_SAMPLES=()
    for dir in "$SCRIPT_DIR/examples/"*/; do
        name="$(basename "$dir")"
        [ "$name" = "local-sample" ] && continue
        [ -f "${dir}sample_mets.xml" ] || continue
        # Copy the directory itself (name + contents) into the data root so each
        # sample lives in its own subdirectory (they share file names).
        cp -R "$SCRIPT_DIR/examples/$name" "$DEMO_DIR/kitodo-demo/"
        sed -i.bak "s|__DATA_BASE__|${DATA_URL}/${name}|g" "$DEMO_DIR/kitodo-demo/${name}/sample_mets.xml" && rm -f "$DEMO_DIR/kitodo-demo/${name}/sample_mets.xml.bak"
        AV3D_SOURCES+=("$name")
        AV3D_SAMPLES+=("${DATA_URL}/${name}/sample_mets.xml")
    done
else
    SAMPLE_URL=""
    AV3D_SOURCES=()
    AV3D_SAMPLES=()
fi

# Build the <option> list for the on-page "Examples" <select>. The digi
# samples are always present; the local sample (when generated) is added as
# the preselected entry, since the URL form is pre-filled with it too.
EXAMPLE_OPTIONS="<option value=\"https://digi.bib.uni-mannheim.de/periodika/fileadmin/data/DeutReunP_856399094_18710504/DeutReunP_856399094_18710504.xml\">Reichsanzeiger, 04.05.1871</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/stefan/DeutReunP_856399094_18920102.xml\">Reichsanzeiger, 02.01.1892</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1885328680/1885328680.xml\">Mannheimer Privilegien, 1652</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1799303241/1799303241.xml\">Gemeinde-Registratur-Ordnung, 1843</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1840280522/1840280522.xml\">Knabenhorten (Vortrag), 1887</option>"
if [ "$MAKE_SAMPLE" = "1" ]; then
    # The local sample is the default (selected) entry and is listed first.
    EXAMPLE_OPTIONS="<option value=\"${SAMPLE_URL}\" selected>Local sample (offline)</option>${EXAMPLE_OPTIONS}"
    # The audio / video / 3D samples follow the image sample, so the on-page
    # selector offers a non page-image example for each media type. Friendly
    # labels are looked up by directory name; unknown ones fall back to the
    # directory name itself.
    av3d_label() {
        case "$1" in
            audio-sample) echo "Audio sample (offline)" ;;
            video-sample) echo "Video sample (offline)" ;;
            model3d-sample) echo "3D model sample (offline)" ;;
            *) echo "$1" ;;
        esac
    }
    for i in "${!AV3D_SOURCES[@]}"; do
        EXAMPLE_OPTIONS="${EXAMPLE_OPTIONS}<option value=\"${AV3D_SAMPLES[$i]}\">$(av3d_label "${AV3D_SOURCES[$i]}")</option>"
    done
fi

# --- write the frontend TypoScript (stored in a sys_template record) ------
log "Writing frontend TypoScript (demo.typoscript)"
cat > demo.typoscript <<'TS'
@import 'EXT:fluid_styled_content/Configuration/TypoScript/setup.typoscript';
@import 'EXT:fluid_styled_content/Configuration/TypoScript/Styling/setup.typoscript';
# NB: FSC's styling TypoScript references {$styles.content.textmedia.*}
# constants. Those resolve against the *constants* tree, so they are loaded
# into the sys_template's `constants` field (see the bootstrap.php below), not
# here — an @import inside this setup tree would not be available for {$...}
# substitution and the placeholders would leak into the served CSS.
@import 'EXT:dlf/Configuration/TypoScript/setup.typoscript';

config {
    pageTitle = 'Kitodo.Presentation demo'
    metaCharset = utf-8
    # cms-frontend's content-length middleware stamps Content-Length =
    # body->getSize() on every FE response. The PageView proxy body is a
    # non-seekable guzzle stream, whose getSize() is null, producing a bogus
    # "Content-Length: 0" that makes clients read an empty body. Disable it
    # so the proxy streams via connection-close / chunked framing.
    enableContentLengthHeader = 0
}

plugin.tx_dlf {
    persistence {
        storagePid = 100
    }
    settings {
        storagePid = 100
    }
}

plugin.tx_dlf_pageview {
    settings {
        # Route image / fulltext / score URLs through the local DLF proxy so
        # they are same-origin. Needed when the document's image host sends
        # no CORS headers, which would otherwise make the browser block the
        # cross-origin canvas render and show a blank viewer.
        useInternalProxy = 1
    }
}

plugin.tx_dlf_navigation {
    settings {
        features = pageFirst,pageBack,pageSelect,pageForward,pageLast,doublePage
        pageStep = 5
    }
}

plugin.tx_dlf_metadata {
    settings {
        # No default exists for this setting (FlexForm only); without it
        # MetadataController::mergeMetadata() throws a TypeError on
        # multivalued metadata.
        separator = #
    }
}

plugin.tx_dlf_toolbox {
    settings {
        # rotationTool / zoomTool always work (plain map view controls); the
        # remaining tools only render buttons when the current document has
        # the matching content (annotation lists, audio/video files, fulltext,
        # 3D model, score file, ...).
        tools = fulltextTool,imageDownloadTool,imageManipulationTool,fulltextDownloadTool,pdfDownloadTool,rotationTool,zoomTool,annotationTool,audioVideoTool,modelDownloadTool,multiViewAddSourceTool,scoreTool,searchInDocumentTool,viewerSelectionTool
        # The fulltext control appends the OCR text to the element named here.
        # It has no default, so without it getElementById("") is null and the
        # text is silently skipped (the region overlay still works, since that
        # is a separate OpenLayers layer). Point it at the fulltext container
        # the PageView template renders (the "#" is kept, as this parser keeps
        # the value verbatim).
        fullTextScrollElement = #tx-dlf-toolbox-fulltext-selection
        # 0 = show the fulltext after clicking the toggle, 1 = on load.
        activateFullTextInitially = 0
    }
}

plugin.tx_dlf_pagegrid {
    settings {
        paginate {
            itemsPerPage = 12
        }
    }
}

# The audio / video media player. It renders nothing for documents that have
# no audio or video file in a configured use group, so it only appears for the
# AV sample documents.
plugin.tx_dlf_mediaplayer {
    settings {
    }
}

# The embedded 3D viewer. It renders nothing unless the current document's
# toplevel type is "object" and page 1 has a model file in the model use group
# (default DEFAULT), so it only appears for the 3D sample document. It falls
# back to the built-in model-viewer for glb / gltf, so no external 3D viewer
# needs to be installed.
plugin.tx_dlf_embedded3dviewer {
    settings {
    }
}

page = PAGE
page.shortcutIcon = kitodo-favicon.ico
page {
    # The floating widget styles (never switched at runtime, so safe to let
    # TYPO3 concatenate). The viewer style itself is NOT included via
    # includeCSS: the widget JS below creates its own <link id="dlf-demo-css">
    # pointing at kitodo-demo/<name>/<name>.css, because TYPO3's asset
    # pipeline concatenates includeCSS files into a single merged-*.css,
    # which a runtime link-href swap could not address.
    includeCSS.dlfDemoWidgets = kitodo-demo/demo-widgets.css
}
page.10 = COA
page.10 {
    10 = TEXT
    10.value = <h1>Kitodo.Presentation viewer</h1><p>Open a document in the viewer. No search / Solr required.</p><form method="get" action=""><label for="dlf-demo-doc">METS / IIIF URL: </label><input type="text" id="dlf-demo-doc" name="tx_dlf[id]" value="__SAMPLE_URL__" size="70"><button type="submit">Open</button></form><p class="dlf-demo-examples"><label for="dlf-demo-example">Examples:</label><select id="dlf-demo-example">__EXAMPLE_OPTIONS__</select></p><div class="dlf-demo-styles"><label for="dlf-demo-style">Style</label><select id="dlf-demo-style" data-base="kitodo-demo/">__STYLE_OPTIONS__</select></div><script>(function(){var s=document.getElementById('dlf-demo-style');if(!s){return;}var K='kitodo-demo-style';var l=document.getElementById('dlf-demo-css');if(!l){l=document.createElement('link');l.id='dlf-demo-css';l.rel='stylesheet';document.head.appendChild(l);}var saved='';try{saved=localStorage.getItem(K);}catch(e){}for(var i=0;i<s.options.length;i++){if(s.options[i].value===saved){s.selectedIndex=i;saved=s.options[i].value;break;}}l.href=s.dataset.base+s.value;s.addEventListener('change',function(){l.href=s.dataset.base+s.value;try{localStorage.setItem(K,s.value);}catch(e){}});})();</script><script>(function(){var s=document.getElementById('dlf-demo-example');var f=document.getElementById('dlf-demo-doc');if(!s||!f){return;}var form=f.form;s.addEventListener('change',function(){f.value=s.value;form.submit();});})();</script>
    # Wrap the content in <div id="main"> so the demo stylesheets can
    # address the plugin frames (#main .frame:has(...)).
    20 = TEXT
    20.value = <div id="main">
    30 < styles.content.get
    40 = TEXT
    40.value = </div>
}
TS
sed -i.bak -e "s|__SAMPLE_URL__|${SAMPLE_URL}|g" -e "s|__EXAMPLE_OPTIONS__|${EXAMPLE_OPTIONS}|g" -e "s|__STYLE_OPTIONS__|${STYLE_OPTIONS}|g" demo.typoscript && rm -f demo.typoscript.bak

# --- write the bootstrap/seed script -------------------------------------
# Patches the FE cache-hash settings and seeds the database (storage page,
# sys_template, viewer plugins). Idempotent.
log "Writing bootstrap.php (settings patch + database seed)"
cat > bootstrap.php <<'PHP'
<?php
declare(strict_types=1);

// 1. Make the DLF viewer render uncached when tx_dlf[id] is present.
//    Without these two settings a viewer request 404s on the missing cHash.
$settingsFile = __DIR__ . '/config/system/settings.php';
if (is_file($settingsFile)) {
    $cfg = require $settingsFile;
    $cfg['FE']['cacheHash']['requireCacheHashPresenceParameters']['tx_dlf[id]'] = true;
    $cfg['FE']['pageNotFoundOnCHashError'] = '0';
    file_put_contents($settingsFile, "<?php return " . var_export($cfg, true) . ";\n");
    echo "settings.php: FE cache-hash patched\n";
}

// 2. Bootstrap TYPO3 for database access.
$classLoader = require __DIR__ . '/vendor/autoload.php';
\TYPO3\CMS\Core\Core\SystemEnvironmentBuilder::run(1, \TYPO3\CMS\Core\Core\SystemEnvironmentBuilder::REQUESTTYPE_CLI);
\TYPO3\CMS\Core\Core\Bootstrap::init($classLoader, true);
$pool = \TYPO3\CMS\Core\Utility\GeneralUtility::makeInstance(\TYPO3\CMS\Core\Database\ConnectionPool::class);

$typoScript = file_get_contents(__DIR__ . '/demo.typoscript');

// 3. Storage page (uid 100), hidden from routing.
$pages = $pool->getConnectionForTable('pages');
$pages->delete('pages', ['uid' => 100]);
$pages->insert('pages', [
    'uid' => 100, 'pid' => 0, 'title' => 'DLF data storage',
    'slug' => '/dlf-data', 'doktype' => 1, 'hidden' => 1,
]);

// 4. Register the metadata formats (pid = storage pid). The type must match
//    the mdWrap @MDTYPE in upper case; without the rows the parser class is
//    unknown and the document's metadata is not parsed ("No supported
//    descriptive metadata found ...").
$formatsTable = $pool->getConnectionForTable('tx_dlf_formats');
$formats = [
    [5001, 'ALTO', 'alto', 'http://www.loc.gov/standards/alto/ns-v2#', 'Kitodo\\Dlf\\Format\\Alto'],
    [5002, 'MODS', 'mods', 'http://www.loc.gov/mods/v3', 'Kitodo\\Dlf\\Format\\Mods'],
];
foreach ($formats as [$uid, $type, $root, $namespace, $class]) {
    $formatsTable->delete('tx_dlf_formats', ['uid' => $uid]);
    $formatsTable->insert('tx_dlf_formats', [
        'uid' => $uid, 'pid' => 100, 'deleted' => 0,
        'type' => $type, 'root' => $root, 'namespace' => $namespace,
        'class' => $class,
    ]);
}

// 4b. Metadata field definitions (tx_dlf_metadata). The dlf_metadata template
//     only renders fields that have a row here (it iterates over the rows to
//     decide what to show). Author / place / year are filled directly by the
//     Mods parser class, so they need no xpath; title and description come
//     from tx_dlf_metadataformat rows (below), one per format, keyed by
//     parent_id -> tx_dlf_metadata.uid and encoded -> tx_dlf_formats.uid.
//     The wrap column is parsed as TypoScript (key. / value. / all.), like
//     in the dfg-viewer seed data.
$metadataTable = $pool->getConnectionForTable('tx_dlf_metadata');
$metadataFormatTable = $pool->getConnectionForTable('tx_dlf_metadataformat');
// The wrap column holds TypoScript (key. / value. / all.). It must contain a
// REAL newline between the key. and value. lines (a literal "\n" would be
// stored verbatim, so use actual line breaks).
$dtdd = "key.wrap = <dt>|</dt>\nvalue.wrap = <dd>|</dd>";
$metadataFields = [
    // uid, label, index_name, wrap, format rows [encoded, xpath], format count
    [5101, 'Title', 'title',
        "key.wrap = <dt class=\"tx-dlf-title\">|</dt>\nvalue.wrap = <dd class=\"tx-dlf-title\">|</dd>",
        [[5002, './mods:titleInfo[not(@type="uniform")]/mods:title']], 1],
    [5102, 'Author', 'author', $dtdd, [], 0],
    [5103, 'Place', 'place', $dtdd, [], 0],
    [5104, 'Year', 'year', $dtdd, [], 0],
    [5105, 'Description', 'description', $dtdd,
        [[5002, './mods:abstract']], 1],
];
foreach ($metadataFields as $n => [$uid, $label, $indexName, $wrap, $formatRows, $formatCount]) {
    $metadataTable->delete('tx_dlf_metadata', ['uid' => $uid]);
    $metadataTable->insert('tx_dlf_metadata', [
        'uid' => $uid, 'pid' => 100, 'deleted' => 0, 'hidden' => 0,
        // mediumblob NOT NULL without a default; SQLite rejects the insert
        // without it (MariaDB fills BLOBs implicitly).
        'l18n_diffsource' => '{}',
        'sorting' => ($n + 1) * 256,
        'label' => $label,
        'index_name' => $indexName,
        'format' => $formatCount,
        'wrap' => $wrap,
        'index_stored' => 1, 'index_indexed' => 1, 'index_boost' => 1,
        'is_listed' => 1,
    ]);
    foreach ($formatRows as $fn => [$encoded, $xpath]) {
        $formatRowUid = 5151 + $n * 2 + $fn;
        $metadataFormatTable->delete('tx_dlf_metadataformat', ['uid' => $formatRowUid]);
        $metadataFormatTable->insert('tx_dlf_metadataformat', [
            'uid' => $formatRowUid, 'pid' => 100, 'deleted' => 0,
            'parent_id' => $uid, 'encoded' => $encoded,
            'xpath' => $xpath,
        ]);
    }
}

// 5. The frontend TypoScript. sys_template is matched by pid in the rootline,
//    so it must be attached to the root page (uid 1), not uid 0.
$templates = $pool->getConnectionForTable('sys_template');
$templates->delete('sys_template', ['uid' => 1]);
$templates->insert('sys_template', [
    'uid' => 1, 'pid' => 1, 'title' => 'DLF template', 'root' => 1,
    // FSC's styling TypoScript (Styling/setup.typoscript) emits CSS that
    // references {$styles.content.textmedia.*} constants. Those resolve against
    // the *constants* tree (this field), not the setup tree, so load FSC's
    // constants file here. Without it TYPO3 leaves the {$...} placeholders
    // literal in the served CSS, which Firefox drops as invalid declarations.
    'constants' => "@import 'EXT:fluid_styled_content/Configuration/TypoScript/constants.typoscript'",
    'config' => $typoScript,
]);

// 6. The viewer is several plugins, each its own tt_content row on the root
//    page. All read the global tx_dlf[id] / tx_dlf[page] params, so none of
//    them need Solr.
$contents = $pool->getConnectionForTable('tt_content');
$plugins = ['dlf_pageview', 'dlf_navigation', 'dlf_pagegrid', 'dlf_metadata', 'dlf_toolbox', 'dlf_mediaplayer', 'dlf_embedded3dviewer'];
foreach ($plugins as $i => $plugin) {
    $uid = 20 + $i;
    $contents->delete('tt_content', ['uid' => $uid]);
    $contents->insert('tt_content', [
        'uid' => $uid, 'pid' => 1, 'CType' => 'list', 'list_type' => $plugin,
        'header' => $plugin, 'sorting' => ($i + 1) * 100,
    ]);
}

echo "seeded: storage page (uid 100), formats + metadata definitions (uid 5001-5155), sys_template (uid 1), viewer plugins (uid 20-24)\n";
PHP

# --- favicon (cosmetic; needs ImageMagick, skipped if absent) -------------
ICON_SRC="$REPO/Resources/Public/Icons/Extension.svg"
if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    IMAGICK="$(command -v magick || command -v convert)"
    mkdir -p public
    if "$IMAGICK" "$ICON_SRC" -define icon:auto-resize=64,48,32,16 public/kitodo-favicon.ico 2>/dev/null; then
        log "Favicon generated"
    else
        warn "ImageMagick could not derive the favicon; continuing without one."
    fi
else
    warn "ImageMagick (magick/convert) not found; skipping favicon."
fi

# --- TYPO3 setup ----------------------------------------------------------
log "Running 'typo3 setup' (database, admin user, site configuration)"
php vendor/bin/typo3 setup -n --force \
    --driver=sqlite \
    --server-type=other \
    --admin-username="$ADMIN_USER" \
    --admin-user-password="$ADMIN_PASSWORD" \
    --project-name="Kitodo.Presentation demo" \
    --create-site="$BASE_URL"

# --- seed -----------------------------------------------------------------
log "Seeding the database (settings patch + pages)"
php bootstrap.php

log "Flushing caches"
php vendor/bin/typo3 cache:flush

log "Demo site ready."
echo
echo "  Site directory : $DEMO_DIR"
echo "  Frontend       : ${BASE_URL}"
echo "  Backend        : ${BASE_URL}typo3"
if [ "$PASSWORD_IS_DEFAULT" = "1" ]; then
    echo "                   (user: $ADMIN_USER, password: $ADMIN_PASSWORD)"
else
    echo "                   (user: $ADMIN_USER, password: <as provided>)"
fi
if [ "$MAKE_SAMPLE" = "1" ]; then
    echo "  Sample document: ${SAMPLE_URL}   (served from ${DEMO_DIR}/kitodo-demo)"
fi
echo "  Viewer style   : $STYLE   (switchable at runtime via the selector on the page)"
echo
if [ "$MAKE_SAMPLE" = "1" ]; then
    echo "  Start the servers (two ports are needed; see the header comment):"
    echo "    php -S 127.0.0.1:$DATA_PORT -t $DEMO_DIR/kitodo-demo $SCRIPT_DIR/assets/data-router.php &"
    echo "    php -S 127.0.0.1:$PORT -t $DEMO_DIR/public"
    echo
    echo "  Then open ${BASE_URL} and click \"Open\" (the sample document is pre-filled)."
else
    echo "  Start the server:"
    echo "    php -S 127.0.0.1:$PORT -t $DEMO_DIR/public"
    echo
    echo "  Then open ${BASE_URL} and paste any METS / IIIF manifest URL into the form."
fi
echo

if [ "$SERVE" = "1" ]; then
    if [ "$MAKE_SAMPLE" = "1" ]; then
        # The router script adds CORS headers to the data server's
        # responses: the media player fetches the media files via XHR from
        # a different port, so without them the browser blocks them.
        php -S "127.0.0.1:$DATA_PORT" -t "$DEMO_DIR/kitodo-demo" "$SCRIPT_DIR/assets/data-router.php" >/dev/null 2>&1 &
        DATA_PID=$!
        trap 'kill "$DATA_PID" 2>/dev/null || true' EXIT
        log "Data server on $DATA_URL (PID $DATA_PID)"
    fi
    log "Starting frontend on $BASE_URL (Ctrl-C to stop)"
    php -S "127.0.0.1:$PORT" -t "$DEMO_DIR/public"
fi
