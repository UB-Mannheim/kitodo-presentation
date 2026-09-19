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
# may fail or return HTML), the script generates a small *local* sample
# document -- a METS file plus three placeholder page images, drawn with PHP
# GD -- and serves it on its own static HTTP port. The on-page form is
# pre-filled with that document's URL, so the viewer works completely
# offline. A *separate* port for the data also sidesteps the built-in PHP
# server's single-threaded self-reference deadlock: the app fetches the METS
# and (via its proxy) the page images server-side, and pointing them at the
# app's own port would stall it.
#
# The script bakes in the workarounds a fresh install otherwise needs
# (documented in AGENTS.md, "Local (no-Docker) test installation"):
#
#   * composer.json relaxes the PHP platform (the extension pins 8.2-8.4,
#     Homebrew ships newer) and pulls dlf from the local checkout as a
#     symlinked `path` repository, plus a `github` repository for
#     ubl/php-iiif-prezi-reader (its tag is not on Packagist).
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
#   --style <name>    Viewer stylesheet to use (default: boxes). The
#                     available styles are the *.css files in Build/Demo/
#                     styles/. All of them are copied into the site, and the
#                     page carries a floating selector so the style can be
#                     switched at runtime. The choice is remembered in
#                     localStorage, so --style is only the default for a
#                     first visit (until the user picks something else).
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
# Styles are the *.css files under Build/Demo/styles/. --style names one of
# them (with or without the .css suffix); it is preselected in the page's
# floating style selector. All stylesheets are copied into the site so the
# selector can switch between them at runtime.
STYLES_DIR="$SCRIPT_DIR/styles"
[ -d "$STYLES_DIR" ] || die "Styles directory not found: $STYLES_DIR"
STYLE_FILE="$STYLES_DIR/$STYLE.css"
[ -f "$STYLE_FILE" ] || die "Unknown style '$STYLE'. Available styles: $(ls "$STYLES_DIR" | sed 's/\.css$//' | tr '\n' ' ')"
# One <option> per stylesheet in Build/Demo/styles/; the current one is
# preselected. New stylesheets are picked up automatically.
STYLE_OPTIONS=""
for f in "$STYLES_DIR/"*.css; do
    name="$(basename "$f" .css)"
    sel=""
    [ "$name" = "$STYLE" ] && sel=" selected"
    STYLE_OPTIONS="${STYLE_OPTIONS}<option value=\"${name}.css\"${sel}>${name}</option>"
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
# All stylesheets (and the widget CSS) are copied verbatim; the page's
# floating selector references them by file name. The --style option only
# decides which one is preselected.
cp "$STYLES_DIR/"*.css "$SCRIPT_DIR/assets/"*.css public/kitodo-demo/

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
# Three placeholder page images (PHP GD) + a METS file pointing at them.
# Served from $DEMO_DIR/kitodo-demo on $DATA_PORT.
if [ "$MAKE_SAMPLE" = "1" ]; then
    log "Generating the local sample document (METS + 3 placeholder pages)"
    cat > make_sample.php <<'PHP'
<?php
declare(strict_types=1);
$dir  = rtrim($argv[1], '/');
$port = (int)$argv[2];
@mkdir($dir, 0755, true);

$font = null;
foreach ([
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
] as $c) {
    if (file_exists($c)) { $font = $c; break; }
}
if ($font === null) {
    $globbed = (array)glob('/usr/share/fonts/**/*.ttf', GLOB_BRACE);
    $font = $globbed ? $globbed[0] : null;
}

function draw_page(string $file, int $num, array $bg, array $fg, ?string $font): void
{
    $im = imagecreatetruecolor(1200, 1600);
    imagefill($im, 0, 0, imagecolorallocate($im, $bg[0], $bg[1], $bg[2]));
    $c = imagecolorallocate($im, $fg[0], $fg[1], $fg[2]);
    if ($font !== null) {
        imagettftext($im, 320, 0, 600, 820, $c, $font, (string)$num);
        imagettftext($im, 52, 0, 90, 1520, $c, $font, "Kitodo.Presentation demo - page $num");
    } else {
        imagestring($im, 5, 560, 780, (string)$num, $c);
        imagestring($im, 5, 60, 1520, "Kitodo.Presentation demo - page $num", $c);
    }
    imagejpeg($im, $file, 85);
}

function draw_thumb(string $file, int $num, array $bg, array $fg, ?string $font): void
{
    // Smaller version for the dlf_pagegrid thumbnail strip.
    $im = imagecreatetruecolor(150, 200);
    imagefill($im, 0, 0, imagecolorallocate($im, $bg[0], $bg[1], $bg[2]));
    $c = imagecolorallocate($im, $fg[0], $fg[1], $fg[2]);
    if ($font !== null) {
        imagettftext($im, 90, 0, 75, 110, $c, $font, (string)$num);
    } else {
        imagestring($im, 5, 65, 90, (string)$num, $c);
    }
    imagejpeg($im, $file, 85);
    imagedestroy($im);
}

draw_page("$dir/page1.jpg", 1, [220, 234, 254], [27, 42, 107], $font);
draw_page("$dir/page2.jpg", 2, [231, 246, 226], [30, 91, 30], $font);
draw_page("$dir/page3.jpg", 3, [253, 233, 230], [122, 31, 18], $font);
draw_thumb("$dir/thumb1.jpg", 1, [220, 234, 254], [27, 42, 107], $font);
draw_thumb("$dir/thumb2.jpg", 2, [231, 246, 226], [30, 91, 30], $font);
draw_thumb("$dir/thumb3.jpg", 3, [253, 233, 230], [122, 31, 18], $font);

// Embed a single JPEG as a one-page PDF. Pure PHP (no ImageMagick / Ghostscript
// dependency), so the demo can build a working "download page (PDF)" button
// offline. The JPEG is embedded verbatim with the /DCTDecode filter.
function write_pdf(string $jpgPath, string $pdfPath, int $w, int $h): void
{
    $jpg  = file_get_contents($jpgPath);
    $len  = strlen($jpg);
    $objs = [
        1 => "<< /Type /Catalog /Pages 2 0 R >>",
        2 => "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3 => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] /Resources << /ProcSet [/PDF /ImageC] /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>",
        4 => "<< /Type /XObject /Subtype /Image /Width $w /Height $h /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length $len >>\nstream\n$jpg\nendstream",
    ];
    $content = "q $w 0 0 $h 0 0 cm /Im0 Do Q";
    $objs[5] = "<< /Length " . strlen($content) . " >>\nstream\n$content\nendstream";

    $pdf = "%PDF-1.3\n";
    $offsets = [];
    for ($i = 1; $i <= 5; $i++) {
        $offsets[$i] = strlen($pdf);
        $pdf .= "$i 0 obj\n" . $objs[$i] . "\nendobj\n";
    }
    $xref = strlen($pdf);
    $pdf .= "xref\n0 6\n0000000000 65535 f \n";
    for ($i = 1; $i <= 5; $i++) {
        $pdf .= sprintf("%010d 00000 n \n", $offsets[$i]);
    }
    $pdf .= "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF";
    file_put_contents($pdfPath, $pdf);
}

write_pdf("$dir/page1.jpg", "$dir/page1.pdf", 1200, 1600);
write_pdf("$dir/page2.jpg", "$dir/page2.pdf", 1200, 1600);
write_pdf("$dir/page3.jpg", "$dir/page3.pdf", 1200, 1600);

// One ALTO file per page, so the FULLTEXT file group is populated. The ALTO
// parser (Kitodo\Dlf\Format\Alto) only reads the <TextBlock> content, so a
// single block with a couple of lines is enough.
function write_alto(string $file, string $text): void
{
    $xml = <<<ALTO
<?xml version="1.0" encoding="UTF-8"?>
<alto xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/standards/alto/ns-v2#">
    <Description><MeasurementUnit>pixel</MeasurementUnit></Description>
    <Layout>
        <Page HEIGHT="1600" WIDTH="1200">
            <PrintSpace HEIGHT="1600" WIDTH="1200" VPOS="0" HPOS="0">
                <TextBlock HEIGHT="100" WIDTH="800" VPOS="100" HPOS="100">
                    <TextLine HEIGHT="80" WIDTH="800" VPOS="100" HPOS="100">
                        <String CONTENT="$text" HEIGHT="80" WIDTH="800" VPOS="100" HPOS="100"/>
                    </TextLine>
                </TextBlock>
            </PrintSpace>
        </Page>
    </Layout>
</alto>
ALTO;
    file_put_contents($file, $xml);
}

$fulltextTexts = [
    1 => 'Page one: this is the full text of the first page of the demo document.',
    2 => 'Page two: this is the full text of the second page of the demo document.',
    3 => 'Page three: this is the full text of the third page of the demo document.',
];
foreach ($fulltextTexts as $i => $text) {
    write_alto("$dir/fulltext_$i.xml", $text);
}

$base  = "http://127.0.0.1:" . $port;
$files = $thumbs = $fulltexts = $downloads = $phys = $sm = $log = '';
for ($i = 1; $i <= 3; $i++) {
    $files     .= sprintf("            <mets:file ID=\"PAGE_%04d\" MIMETYPE=\"image/jpeg\">\n                <mets:FLocat LOCTYPE=\"URL\" xlink:href=\"%s/page%d.jpg\"/>\n            </mets:file>\n", $i, $base, $i);
    $thumbs    .= sprintf("            <mets:file ID=\"PAGE_%04d_THUMBS\" MIMETYPE=\"image/jpeg\">\n                <mets:FLocat LOCTYPE=\"URL\" xlink:href=\"%s/thumb%d.jpg\"/>\n            </mets:file>\n", $i, $base, $i);
    $fulltexts .= sprintf("            <mets:file ID=\"PAGE_%04d_FULLTEXT\" MIMETYPE=\"text/xml\">\n                <mets:FLocat LOCTYPE=\"URL\" xlink:href=\"%s/fulltext_%d.xml\"/>\n            </mets:file>\n", $i, $base, $i);
    $downloads .= sprintf("            <mets:file ID=\"PAGE_%04d_DOWNLOAD\" MIMETYPE=\"application/pdf\">\n                <mets:FLocat LOCTYPE=\"URL\" xlink:href=\"%s/page%d.pdf\"/>\n            </mets:file>\n", $i, $base, $i);
    $phys      .= sprintf("                <mets:div ID=\"PHYS_%04d\" ORDER=\"%d\" TYPE=\"page\">\n                    <mets:fptr FILEID=\"PAGE_%04d\"/>\n                    <mets:fptr FILEID=\"PAGE_%04d_THUMBS\"/>\n                    <mets:fptr FILEID=\"PAGE_%04d_FULLTEXT\"/>\n                    <mets:fptr FILEID=\"PAGE_%04d_DOWNLOAD\"/>\n                </mets:div>\n", $i, $i, $i, $i, $i, $i);
    $sm        .= sprintf("        <mets:smLink xlink:from=\"LOG_000%d\" xlink:to=\"PHYS_%04d\"/>\n", $i, $i);
    $log       .= sprintf("            <mets:div ID=\"LOG_000%d\" LABEL=\"Page %d\" TYPE=\"page\"/>\n", $i, $i);
}

$mets = <<<XML
<?xml version="1.0" encoding="UTF-8"?>
<mets:mets xmlns:mets="http://www.loc.gov/METS/" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <mets:dmdSec ID="DMD_0001">
        <mets:mdWrap MDTYPE="MODS">
            <mets:xmlData>
                <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
                    <mods:titleInfo><mods:title>Kitodo.Presentation demo document</mods:title></mods:titleInfo>
                    <mods:name><mods:namePart>Kitodo. Key to digital objects e.V.</mods:namePart></mods:name>
                    <mods:typeOfResource>manuscript</mods:typeOfResource>
                    <mods:originInfo><mods:place><mods:placeTerm>Mannheim</mods:placeTerm></mods:place><mods:dateIssued>2026</mods:dateIssued></mods:originInfo>
                    <mods:abstract>A locally generated sample document with three placeholder pages. All metadata shown in the demo viewer is part of this document.</mods:abstract>
                </mods:mods>
            </mets:xmlData>
        </mets:mdWrap>
    </mets:dmdSec>
    <mets:fileSec>
        <mets:fileGrp USE="DEFAULT">
$files        </mets:fileGrp>
        <mets:fileGrp USE="THUMBS">
$thumbs        </mets:fileGrp>
        <mets:fileGrp USE="FULLTEXT">
$fulltexts        </mets:fileGrp>
        <mets:fileGrp USE="DOWNLOAD">
$downloads        </mets:fileGrp>
    </mets:fileSec>
    <mets:structMap TYPE="LOGICAL">
        <mets:div ID="LOG_0000" DMDID="DMD_0001" LABEL="Kitodo.Presentation demo document" TYPE="monograph">
            <mets:fptr FILEID="PAGE_0001_DOWNLOAD"/>
$log        </mets:div>
    </mets:structMap>
    <mets:structMap TYPE="PHYSICAL">
        <mets:div ID="PHYS_0000" TYPE="physSequence">
$phys        </mets:div>
    </mets:structMap>
    <mets:structLink>
$sm    </mets:structLink>
</mets:mets>
XML;
file_put_contents("$dir/sample_mets.xml", $mets);
echo "sample document written to $dir (3 pages; METS at $base/sample_mets.xml)\n";
PHP
    php make_sample.php "$DEMO_DIR/kitodo-demo" "$DATA_PORT"
    SAMPLE_URL="${DATA_URL}/sample_mets.xml"
else
    SAMPLE_URL=""
fi

# --- write the frontend TypoScript (stored in a sys_template record) ------
log "Writing frontend TypoScript (demo.typoscript)"
cat > demo.typoscript <<'TS'
@import 'EXT:fluid_styled_content/Configuration/TypoScript/setup.typoscript';
@import 'EXT:fluid_styled_content/Configuration/TypoScript/Styling/setup.typoscript';
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
        tools = fulltextTool,imageDownloadTool,imageManipulationTool,fulltextDownloadTool,pdfDownloadTool
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

page = PAGE
page.shortcutIcon = kitodo-favicon.ico
page {
    # The floating widget styles (never switched at runtime, so safe to let
    # TYPO3 concatenate). The viewer style itself is NOT included via
    # includeCSS: the widget JS below creates its own <link id="dlf-demo-css">
    # pointing at kitodo-demo/<name>.css, because TYPO3's asset pipeline
    # concatenates includeCSS files into a single merged-*.css, which a
    # runtime link-href swap could not address.
    includeCSS.dlfDemoWidgets = kitodo-demo/demo-widgets.css
}
page.10 = COA
page.10 {
    10 = TEXT
    10.value = <h1>Kitodo.Presentation viewer</h1><p>Open a document in the viewer. No search / Solr required.</p><form method="get" action=""><label for="dlf-demo-doc">METS / IIIF URL: </label><input type="text" id="dlf-demo-doc" name="tx_dlf[id]" value="__SAMPLE_URL__" size="70"><button type="submit">Open</button></form><div class="dlf-demo-styles"><label for="dlf-demo-style">Style</label><select id="dlf-demo-style" data-base="kitodo-demo/">__STYLE_OPTIONS__</select></div><script>(function(){var s=document.getElementById('dlf-demo-style');if(!s){return;}var K='kitodo-demo-style';var l=document.getElementById('dlf-demo-css');if(!l){l=document.createElement('link');l.id='dlf-demo-css';l.rel='stylesheet';document.head.appendChild(l);}var saved='';try{saved=localStorage.getItem(K);}catch(e){}for(var i=0;i<s.options.length;i++){if(s.options[i].value===saved){s.selectedIndex=i;saved=s.options[i].value;break;}}l.href=s.dataset.base+s.value;s.addEventListener('change',function(){l.href=s.dataset.base+s.value;try{localStorage.setItem(K,s.value);}catch(e){}});})();</script>
    # Wrap the content in <div id="main"> so the demo stylesheets can
    # address the plugin frames (#main .frame:has(...)).
    20 = TEXT
    20.value = <div id="main">
    30 < styles.content.get
    40 = TEXT
    40.value = </div>
}
TS
sed -i.bak -e "s|__SAMPLE_URL__|${SAMPLE_URL}|g" -e "s|__STYLE_OPTIONS__|${STYLE_OPTIONS}|g" demo.typoscript && rm -f demo.typoscript.bak

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
    'constants' => '', 'config' => $typoScript,
]);

// 6. The viewer is several plugins, each its own tt_content row on the root
//    page. All read the global tx_dlf[id] / tx_dlf[page] params, so none of
//    them need Solr.
$contents = $pool->getConnectionForTable('tt_content');
$plugins = ['dlf_pageview', 'dlf_navigation', 'dlf_pagegrid', 'dlf_metadata', 'dlf_toolbox'];
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
    echo "    php -S 127.0.0.1:$DATA_PORT -t $DEMO_DIR/kitodo-demo &"
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
        php -S "127.0.0.1:$DATA_PORT" -t "$DEMO_DIR/kitodo-demo" >/dev/null 2>&1 &
        DATA_PID=$!
        trap 'kill "$DATA_PID" 2>/dev/null || true' EXIT
        log "Data server on $DATA_URL (PID $DATA_PID)"
    fi
    log "Starting frontend on $BASE_URL (Ctrl-C to stop)"
    php -S "127.0.0.1:$PORT" -t "$DEMO_DIR/public"
fi
