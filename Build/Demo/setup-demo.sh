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
#   --base-url <url>  Serve the site under a public base URL instead of the
#                     localhost dev server (e.g. https://host.example/demo/
#                     when an Apache vhost or reverse proxy fronts the site).
#                     It becomes the TYPO3 site base, and the web server must
#                     serve $DEMO_DIR/public at that URL. --serve is not
#                     allowed with this option.
#   --data-url <url>  Public base URL of the sample data files
#                     ($DEMO_DIR/kitodo-demo), e.g.
#                     https://host.example/demo-data. Required with --base-url
#                     unless --no-sample is given.
#   --branch <name>   dlf branch to install (default: current git branch)
#   --user <name>     Backend admin username (default: admin)
#   --password <pw>   Backend admin password. For localhost installs (no
#                     --base-url) the default demo-Passw0rd! is used when it
#                     is not given; for web installations (--base-url) a
#                     random password is generated and printed at the end if
#                     none is given (must satisfy TYPO3 policy).
#   --style <name>    Viewer theme to use (default: aurora). The available
 #                     themes are the subdirectories of Build/Demo/styles/;
 #                     each one holds its main stylesheet <name>.css and may
 #                     carry further assets (images, scripts, ...). All
 #                     themes are copied into the site, and the page carries
 #                     a floating selector so the theme can be switched at
 #                     runtime. A "Dark" checkbox next to it toggles dark
 #                     mode for styles that support it (e.g. aurora). The
 #                     choices are remembered in localStorage, so --style is
 #                     only the default for a first visit (until the user
 #                     picks something else).
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
STYLE="aurora"
BRANCH="$(git -C "$REPO" branch --show-current 2>/dev/null || true)"
BRANCH="${BRANCH:-main}"
ADMIN_USER="admin"
DEFAULT_PASSWORD="demo-Passw0rd!"
# The password is resolved later, once it is known whether the site is served
# on localhost (default password allowed) or publicly via --base-url (a web
# installation must not use the default password). An explicit --password (or
# ADMIN_PASSWORD env var) always wins.
if [ -n "${ADMIN_PASSWORD:-}" ]; then
    PASSWORD_EXPLICIT=1
else
    ADMIN_PASSWORD="$DEFAULT_PASSWORD"
    PASSWORD_EXPLICIT=0
fi
PASSWORD_GENERATED=0
SERVE=0
MAKE_SAMPLE=1
BASE_URL=""
DATA_URL=""

usage() { awk 'NR==1{next} /^set -euo/{exit} {sub(/^# ?/,""); print}' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DEMO_DIR="$2"; shift 2 ;;
        --port) DEMO_PORT="$2"; shift 2 ;;
        --base-url) BASE_URL="$2"; shift 2 ;;
        --data-url) DATA_URL="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --user) ADMIN_USER="$2"; shift 2 ;;
        --password) ADMIN_PASSWORD="$2"; PASSWORD_EXPLICIT=1; shift 2 ;;
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

# --- pick ports / base URLs ----------------------------------------------
# By default the site is served by the built-in PHP dev server on localhost.
# With --base-url the site is served by a real web server (Apache, ...) that
# frontends $DEMO_DIR/public at the given URL; the sample data must then be
# reachable at --data-url (e.g. via an Apache Alias) and the dev servers are
# not started.
PUBLIC_BASE=0
if [ -n "$BASE_URL" ]; then
    PUBLIC_BASE=1
    # A web installation must not ship with the well-known demo password.
    # With no explicit --password / ADMIN_PASSWORD, generate a secure random
    # one (24 chars from a set that satisfies the TYPO3 password policy:
    # lower/upper case, digit, special character) and print it at the end.
    if [ "$PASSWORD_EXPLICIT" = "0" ]; then
        # Reuse the password generated by a previous run (stored in the site
        # directory) so re-running the script does not reset the admin
        # password; generate a new one only if none is stored.
        if [ -f "$DEMO_DIR/.admin-password" ]; then
            ADMIN_PASSWORD="$(cat "$DEMO_DIR/.admin-password")"
        else
            # 24 random characters from a set containing lower case, upper
            # case, digits and a special character; retry until all four
            # character classes are present (satisfies the TYPO3 password
            # policy). pipefail is disabled in the subshell because `head -c`
            # exits before `tr` drains /dev/urandom, and the resulting
            # SIGPIPE (141) would abort the script under `set -o pipefail`.
            ADMIN_PASSWORD="$(
                set +o pipefail
                while :; do
                    p="$(LC_ALL=C tr -dc 'A-Za-z0-9!' </dev/urandom | head -c 24)"
                    case "$p" in
                        *[a-z]*[A-Z]*[0-9]*[![:alnum:]]*) break ;;
                    esac
                done
                printf '%s' "$p"
            )"
            mkdir -p "$DEMO_DIR"
            printf '%s' "$ADMIN_PASSWORD" > "$DEMO_DIR/.admin-password"
            chmod 600 "$DEMO_DIR/.admin-password"
        fi
        PASSWORD_EXPLICIT=1
        PASSWORD_GENERATED=1
    fi
    case "$BASE_URL" in
        http://*|https://*) ;;
        *) die "--base-url must be an absolute http(s) URL (trailing slash recommended)." ;;
    esac
    case "$BASE_URL" in
        */) ;;
        *) warn "--base-url should end with a slash; appending one."
           BASE_URL="${BASE_URL}/" ;;
    esac
    [ "$SERVE" = "1" ] && die "--serve cannot be used with --base-url (the external web server serves the site)."
    if [ "$MAKE_SAMPLE" = "1" ]; then
        [ -n "$DATA_URL" ] || die "--data-url is required with --base-url (unless --no-sample is given)."
        case "$DATA_URL" in
            http://*|https://*) ;;
            *) die "--data-url must be an absolute http(s) URL." ;;
        esac
    fi
elif [ -n "$DATA_URL" ]; then
    die "--data-url is only meaningful with --base-url."
else
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
fi

# --- create the project --------------------------------------------------
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"

mkdir -p public/kitodo-demo
# All styles (each a directory, copied verbatim so any extra theme assets
# come along) and the widget CSS are copied; the page's floating selector
# references them by <style>/<style>.css. The --style option only decides
# which one is preselected. (No trailing slash on the glob, so the style
# *directories* are copied, not their contents.)
cp -R "$STYLES_DIR"/* "$SCRIPT_DIR/assets/"*.{css,js} public/kitodo-demo/

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
    # The newspaper sample is the ideal single anchor METS (whole newspaper,
    # all years) plus one year METS per year; each year file covers all issues
    # of that year and links them to the live digi issue documents.
    NEWS_DIR="$SCRIPT_DIR/examples/newspaper"
    cp "$NEWS_DIR/DeutReunP_856399094_anchor.xml" "$DEMO_DIR/kitodo-demo/"
    # Year files are optional; guard the glob so a checkout without them (e.g. a
    # pre-newspaper-sample revision) does not leave it as a literal path and
    # break the copy / sed below.
    shopt -s nullglob
    NEWS_YEAR_FILES=("$NEWS_DIR"/DeutReunP_856399094_*_year.xml)
    shopt -u nullglob
    [ "${#NEWS_YEAR_FILES[@]}" -gt 0 ] && cp "${NEWS_YEAR_FILES[@]}" "$DEMO_DIR/kitodo-demo/"
    for f in DeutReunP_856399094_anchor.xml "${NEWS_YEAR_FILES[@]##*/}"; do
        sed -i.bak "s|__DATA_BASE__|${DATA_URL}|g" "$DEMO_DIR/kitodo-demo/$f" && rm -f "$DEMO_DIR/kitodo-demo/$f.bak"
    done
    NEWS_ANCHOR_URL="${DATA_URL}/DeutReunP_856399094_anchor.xml"
else
    SAMPLE_URL=""
    AV3D_SOURCES=()
    AV3D_SAMPLES=()
    NEWS_ANCHOR_URL=""
fi

# Build the <option> list for the on-page "Examples" <select>. The digi
# samples are always present; the local samples (when generated) are added
# after them. Nothing is preselected: a hidden blank placeholder option keeps
# the select from implying a document is already open, and the inline script
# (below) syncs the selection with the URL form in both directions.
EXAMPLE_OPTIONS="<option value=\"https://digi.bib.uni-mannheim.de/periodika/fileadmin/data/DeutReunP_856399094_18710504/DeutReunP_856399094_18710504.xml\">Reichsanzeiger, 04.05.1871</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1885328680/1885328680.xml\">Mannheimer Privilegien, 1652</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1799303241/1799303241.xml\">Gemeinde-Registratur-Ordnung, 1843</option><option value=\"https://digi.bib.uni-mannheim.de/fileadmin/digi/1840280522/1840280522.xml\">Knabenhorten (Vortrag), 1887</option>"
if [ "$MAKE_SAMPLE" = "1" ]; then
    EXAMPLE_OPTIONS="${EXAMPLE_OPTIONS}<option value=\"${SAMPLE_URL}\">Local sample (offline)</option>"
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
    # The newspaper anchor (toplevel type "newspaper") drives the calendar's
    # years view and the table of contents' full hierarchy, so it is the
    # offline example of the periodical navigation.
    EXAMPLE_OPTIONS="${EXAMPLE_OPTIONS}<option value=\"${NEWS_ANCHOR_URL}\">Reichsanzeiger (newspaper anchor, offline)</option>"
fi
# The hidden placeholder is listed first so the select renders blank until
# the user picks an example (a plain disabled placeholder is still "selected"
# by default, so the browser would show it; `hidden` keeps it out of the
# display while keeping it a valid reset target).
EXAMPLE_OPTIONS="<option value=\"\" hidden></option>${EXAMPLE_OPTIONS}"

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

# The table of contents. For newspaper issues it renders the whole logical
# hierarchy (newspaper -> year -> month -> day -> issue); entries whose METS
# node carries an mptr (the toplevel newspaper node and the year node) link to
# the external anchor / year overview documents.
plugin.tx_dlf_tableofcontents {
    settings {
        storagePid = 100
        # Expand the full hierarchy instead of only the active branch.
        showFull = 1
    }
}

# The calendar. It is the newspaper overview: opened with the anchor document
# (toplevel type "newspaper") it lists all years (dlf_calendar years view);
# opened with a year document (toplevel type "year") it shows the day calendar
# of that year's issues. Neither view needs Solr — when the documents are not
# indexed they fall back to the mptr links in the METS table of contents.
plugin.tx_dlf_calendar {
    settings {
        storagePid = 100
        # Do not pad the year list with empty decades.
        showEmptyYears = 0
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

# The OAI-PMH endpoint (a Solr-backed OAI provider; it serves raw OAI-PMH XML
# from the /oai page, which gets a raw-XML TypoScript override further below).
plugin.tx_dlf_oaipmh {
    settings {
        title = Kitodo.Presentation demo OAI-PMH
        storagePid = 100
        limit = 5
        expired = 1800
        solrLimit = 50000
    }
}

# The validation form. It validates an arbitrary XML document URL against the
# configured validators and lists the results. The demo wires up the pure-PHP
# XmlSchemasValidator (no Java needed) with the METS / MODS / XLink schemas from
# the committed test fixtures, referenced by file:// to this checkout (always
# present, since dlf is symlinked in from here). The form is an ordinary HTML
# page (unlike /oai), so it needs no raw-XML TypoScript override.
#
# The form submits the validation type as the GET param "type", which is also
# TYPO3's reserved page-typeNum param: a non-numeric value makes
# PrepareTypoScriptFrontendRendering 500 ("No page configured for type=...")
# before the dlf middleware ever runs. The demo has no site routes, so the type
# is named "0" -- a valid typeNum (the root page) and a valid config key -- so
# the request resolves and the middleware can intercept it.
plugin.tx_dlf_validationform {
    settings {
        # The validation type the form submits; it is looked up under
        # plugin.tx_dlf.settings.domDocumentValidation (below). Must be numeric
        # (see the note above) -- "0" doubles as the root page's typeNum.
        type = 0
    }
}
plugin.tx_dlf.settings {
    domDocumentValidation {
        0 {
            10 {
                title = METS / MODS / XLink (XSD)
                description = Validates the document against the METS, MODS and XLink XML schemas.
                className = Kitodo\Dlf\Validation\XmlSchemasValidator
                configuration {
                    mets {
                        namespace = http://www.loc.gov/METS/
                        schemaLocation = file://__REPO__/Tests/Fixtures/Schemas/mets.xsd
                    }
                    mods {
                        namespace = http://www.loc.gov/mods/v3
                        schemaLocation = file://__REPO__/Tests/Fixtures/Schemas/mods.xsd
                    }
                    xlink {
                        namespace = http://www.w3.org/1999/xlink
                        schemaLocation = file://__REPO__/Tests/Fixtures/Schemas/xlink.xsd
                    }
                }
            }
        }
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
    # The widget JS is an external file (not inline in the TEXT cObject below)
    # because TYPO3's HTML sanitizer mangles inline <script> blocks (it strips
    # the curly braces of JS function bodies).
    includeJSFooter.dlfDemoWidgets = kitodo-demo/demo-widgets.js
}
# The page body differs per page, selected by the page uid: the root page (uid
# 1) shows the viewer scaffold and widgets; /oai (uid 101) is a raw OAI-PMH XML
# endpoint; /validation (uid 102) is a plain page with only the form.
[page['uid'] == 1]
page.10 = COA
page.10 {
    10 = TEXT
    10 {
        value = <h1><a href="/">Kitodo.Presentation viewer</a></h1><p>Open a document in the viewer. No search / Solr required.</p><p class="dlf-demo-links"><a href="/oai">OAI-PMH</a> &middot; <a href="/validation">XML validation</a></p><form method="get" action=""><label for="dlf-demo-doc">METS / IIIF URL: </label><input type="text" id="dlf-demo-doc" name="tx_dlf[id]" value="__SAMPLE_URL__" size="70"><button type="submit">Open</button></form><p class="dlf-demo-examples"><label for="dlf-demo-example">Examples:</label><select id="dlf-demo-example">__EXAMPLE_OPTIONS__</select></p><div class="dlf-demo-styles"><label for="dlf-demo-style">Style</label><select id="dlf-demo-style" data-base="kitodo-demo/">__STYLE_OPTIONS__</select><label for="dlf-demo-dark"><input type="checkbox" id="dlf-demo-dark">Dark</label></div>
        insertData = 1
        htmlSanitize = 0
    }
    # Wrap the content in <div id="main"> so the demo stylesheets can
    # address the plugin frames (#main .frame:has(...)).
    20 = TEXT
    20.value = <div id="main">
    30 < styles.content.get
    40 = TEXT
    40.value = </div>
}
[end]

# /oai: an OAI-PMH endpoint, not a normal HTML page. The controller forces the
# response to XML; this block strips the HTML scaffolding (doctype, <html>,
# head, content wrap) and sets the Content-Type so the page is pure OAI-PMH XML.
[page['uid'] == 101]
config {
    disableAllHeaderCode = 1
    xhtml_cleaning = none
    admPanel = 0
    debug = 0
    metaCharset = utf-8
    additionalHeaders.10.header = Content-Type:text/xml;charset=utf-8
    disablePrefixComment = 1
    linkVars >
}
page.10 < styles.content.get
tt_content.stdWrap >
tt_content.stdWrap.editPanel = 0
lib.contentElement.templateRootPaths.5 = EXT:dlf/Resources/Private/fluid_styled_content/Templates
[end]

# /validation: a plain page (no viewer scaffold) showing only the form. The
# form's URL field is pre-filled with the local sample METS by the widget JS,
# which reads the URL from the data-sample attribute on this marker element
# (the sample URL is baked at setup time, so it cannot live in the static JS).
[page['uid'] == 102]
page.10 = COA
page.10 {
    10 = TEXT
    10 {
        value = <h1>XML document validation</h1><p>Paste a METS / IIIF / any XML document URL below (the local sample is pre-filled) and click <strong>Validate</strong>. The result appears underneath the form.</p><div id="dlf-demo-validation" data-sample="__SAMPLE_URL__" hidden></div>
        insertData = 1
        htmlSanitize = 0
    }
    20 = TEXT
    20.value = <div id="main">
    30 < styles.content.get
    40 = TEXT
    40.value = </div>
}
[end]
TS
sed -i.bak -e "s|__SAMPLE_URL__|${SAMPLE_URL}|g" -e "s|__EXAMPLE_OPTIONS__|${EXAMPLE_OPTIONS}|g" -e "s|__STYLE_OPTIONS__|${STYLE_OPTIONS}|g" -e "s|__REPO__|${REPO}|g" demo.typoscript && rm -f demo.typoscript.bak

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
// Subpages of the root page (uid 1). Each carries a special layout selected by
// the [page['uid'] == ...] blocks in the TypoScript above.
$pages->delete('pages', ['uid' => 101]);
$pages->insert('pages', [
    'uid' => 101, 'pid' => 1, 'title' => 'OAI-PMH',
    'slug' => '/oai', 'doktype' => 1, 'hidden' => 0,
]);
$pages->delete('pages', ['uid' => 102]);
$pages->insert('pages', [
    'uid' => 102, 'pid' => 1, 'title' => 'XML validation',
    'slug' => '/validation', 'doktype' => 1, 'hidden' => 0,
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

// 4c. Logical structure types (tx_dlf_structures). The table of contents
//     controller looks these up (by index_name + storage pid) to translate the
//     raw METS @TYPE (newspaper/year/month/day/issue) into human labels and to
//     order the newspaper branch. Without the rows it falls back to the raw
//     type string and skips the year sort. "newspaper" is marked toplevel so
//     the indexer would treat it as the document root.
$structuresTable = $pool->getConnectionForTable('tx_dlf_structures');
$structures = [
    [6001, 'Newspaper', 'newspaper', 1],
    [6002, 'Year', 'year', 0],
    [6003, 'Month', 'month', 0],
    [6004, 'Day', 'day', 0],
    [6005, 'Issue', 'issue', 0],
];
foreach ($structures as [$uid, $label, $indexName, $toplevel]) {
    $structuresTable->delete('tx_dlf_structures', ['uid' => $uid]);
    $structuresTable->insert('tx_dlf_structures', [
        'uid' => $uid, 'pid' => 100, 'deleted' => 0, 'hidden' => 0,
        'sys_language_uid' => 0, 'l18n_diffsource' => '{}',
        'toplevel' => $toplevel, 'label' => $label, 'index_name' => $indexName,
        'status' => 0,
    ]);
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
$plugins = ['dlf_pageview', 'dlf_navigation', 'dlf_pagegrid', 'dlf_tableofcontents', 'dlf_calendar', 'dlf_metadata', 'dlf_toolbox', 'dlf_mediaplayer', 'dlf_embedded3dviewer'];
foreach ($plugins as $i => $plugin) {
    $uid = 20 + $i;
    $contents->delete('tt_content', ['uid' => $uid]);
    $contents->insert('tt_content', [
        'uid' => $uid, 'pid' => 1, 'CType' => 'list', 'list_type' => $plugin,
        'header' => $plugin, 'sorting' => ($i + 1) * 100,
    ]);
}
// 6b. The OAI-PMH plugin on the /oai page and the validation form on the
//     /validation page (each a single tt_content row on its subpage).
$contents->delete('tt_content', ['uid' => 29]);
$contents->insert('tt_content', [
    'uid' => 29, 'pid' => 101, 'CType' => 'list', 'list_type' => 'dlf_oaipmh',
    'header' => 'OAI-PMH', 'sorting' => 100,
]);
$contents->delete('tt_content', ['uid' => 30]);
$contents->insert('tt_content', [
    'uid' => 30, 'pid' => 102, 'CType' => 'list', 'list_type' => 'dlf_validationform',
    'header' => 'XML validation', 'sorting' => 100,
]);

echo "seeded: storage page (uid 100), subpages (uid 101 /oai, 102 /validation), formats + metadata definitions (uid 5001-5155), structures (uid 6001-6005), sys_template (uid 1), viewer plugins (uid 20-28), oai (uid 29) + validation (uid 30) plugins\n";
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
if [ "$PASSWORD_GENERATED" = "1" ]; then
    echo "                   (user: $ADMIN_USER, password: $ADMIN_PASSWORD)"
    echo "                    (generated because no password was given for a web"
    echo "                     installation; change it in the backend)"
elif [ "$PASSWORD_EXPLICIT" = "1" ]; then
    echo "                   (user: $ADMIN_USER, password: <as provided>)"
else
    echo "                   (user: $ADMIN_USER, password: $ADMIN_PASSWORD)"
fi
if [ "$MAKE_SAMPLE" = "1" ]; then
    echo "  Sample document: ${SAMPLE_URL}   (files in ${DEMO_DIR}/kitodo-demo)"
fi
echo "  Viewer style   : $STYLE   (switchable at runtime via the selector on the page)"
echo
if [ "$PUBLIC_BASE" = "1" ]; then
    # The external web server serves the site; make the site and var/
    # (SQLite database, caches) readable/writable by its user.
    if [ "$(id -un)" = "root" ]; then
        chown -R www-data:www-data "$DEMO_DIR" 2>/dev/null || warn "Could not chown $DEMO_DIR to www-data; do it manually if the web server cannot write var/."
    else
        warn "Make $DEMO_DIR (especially var/) writable by your web server's user so it can write the SQLite database and caches."
    fi
    echo "  The web server must serve ${DEMO_DIR}/public at ${BASE_URL}"
    if [ "$MAKE_SAMPLE" = "1" ]; then
        echo "  and ${DEMO_DIR}/kitodo-demo at ${DATA_URL} (e.g. Apache:"
        echo
        echo "      Alias /demo       $DEMO_DIR/public"
        echo "      Alias /demo-data  $DEMO_DIR/kitodo-demo"
        echo
        echo "  ), then flush the caches if the URLs change:"
        echo "      php vendor/bin/typo3 cache:flush"
        echo "      (in ${DEMO_DIR})."
    fi
    echo
    echo "  Then open ${BASE_URL}"
    if [ "$MAKE_SAMPLE" = "1" ]; then
        echo "  and click \"Open\" (the sample document is pre-filled)."
    else
        echo "  and paste any METS / IIIF manifest URL into the form."
    fi
else
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
