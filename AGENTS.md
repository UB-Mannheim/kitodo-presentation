# AGENTS.md

## What this is

TYPO3 CMS extension (extension key **`dlf`**), not a plain app. PHP 8.2–8.4,
TYPO3 12.4/13.4. `Classes/` maps to namespace `Kitodo\Dlf\` — the directory
name does not match the vendor prefix. `Tests/` mirrors `Classes/` with
namespace `Kitodo\Dlf\Tests\`. The repo is large but only `Classes/`,
`Configuration/`, `Resources/`, `Tests/`, `Build/` and `public/` are
extension source; everything else (e.g. `typo3_13.4/`, `madabi/`, `contrib/`,
`issues/`, loose `*.patch` files, files `1`/`2`) is local working scratch,
not part of the extension.

This local checkout is a UB Mannheim fork. Remotes: `kitodo` (upstream
github.com/kitodo/kitodo-presentation), `origin` (stweil's fork), `UB-Mannheim`
and `code` (code.bib.uni-mannheim.de:digi/typo3.git). Upstream `main` is being
adapted for TYPO3 14; many local branches (incl. current `ubma/*` ones) target
TYPO3 12.4. Commit subjects follow `BUGFIX:` / `FEATURE:` / `TASK:` /
`MAINTENANCE:` scope prefixes.

## Running the extension locally

- Local TYPO3 install for manual work lives in `typo3_13.4/` (composer
  project, gitignored). Extension code is reached via the symlink
  `public/typo3conf/ext/dlf -> ../..`, recreated by the composer
  `post-autoload-dump` script — don't delete `public/typo3conf/ext/dlf`.
- CLI commands from the TYPO3 install dir (not this repo):
  `vendor/bin/typo3 kitodo:dbdocs` regenerates
  `Documentation/Developers/Database.rst`.
- `ext_tables.sql` / TCA changes: dbdocs is generated, never hand-edit the
  generated doc page.

## Tests (Docker)

- `composer install-via-docker -- -t 12.4` (or `-t 13.4`) must run before any
  test; it reinstalls `vendor/` for that TYPO3 version.
- `composer test:unit` / `composer test:func` run `Build/Test/runTests.sh`,
  which spawns and tears down a docker compose stack (MariaDB/MySQL + Solr
  9.7 for functional tests). Solr config comes from
  `Configuration/ApacheSolr/configsets`; functional tests expect Solr at
  `solr:8983` inside the stack — they will not run without it.
- Single test file: `Build/Test/runTests.sh -s unit Tests/Unit/Foo/BarTest.php`
  (same pattern for `-s functional`); extra PHPUnit args via
  `-e "-v --filter testFoo"`; `-w` for watch mode; `-p 8.2|8.3|8.4`.
- Unit tests can also run locally (if PHP + vendor match):
  `composer test:unit:local`, or
  `vendor/bin/phpunit -c Build/Test/UnitTests.xml Tests/Unit/...`.
- Functional tests only run via Docker (`composer test:func`).
- Functional tests need a second web server on port 8001 (started by
  docker-compose) for `PageViewProxy` tests; don't assume port 8000 is the
  only one in use.
- Fixture datasets in `Tests/Fixtures`: use large, unique, grep-able `uid`s
  to avoid merge conflicts (convention in existing fixtures).

## JavaScript (webpack, under `Build/`)

- Source: `Resources/Private/JavaScript/`; output:
  `Resources/Public/JavaScript/DlfMediaPlayer/` + `Resources/Public/Css/`.
- **Built assets are committed to the repo.** A push to upstream `main`
  triggers `webpack-main-build-and-commit.yaml`, which rebuilds and commits
  them as `webpack-builder[bot]`. On PRs the build only checks.
- Trap: the `DlfMediaPlayer` webpack entry actually compiles
  `Resources/Private/JavaScript/SlubMediaPlayer/` (a rename that never
  finished). Don't "fix" paths based on the bundle name alone.
- `Build/` is a separate npm project (its own `package.json`, `.nvmrc` —
  install there with `npm ci`, not in the repo root):
  - `npm run build` (production), `npm run watch` (dev)
  - `npm run typecheck` (tsc via `../jsconfig.json` — run from `Build/`)
  - `npm test` (jest; rootDir is the repo root, roots
    `Resources/Private/JavaScript`)
  - `npm run compat` / `npm run compat-build` (eslint browser-compat checks)
- The webpack dev server (`npm run serve`, port 9000) runs **HTTPS** —
  required for AudioWorklet (Equalizer) testing.

## QA

- PHPStan: `composer phpstan` runs with `.github/phpstan_13.4.neon`;
  `.github/phpstan_12.4.neon` is the TYPO3 12.4 variant — pick the config
  matching the installed TYPO3. CI checks both.
- PSR-12 via PHP CS Fixer (`composer php-cs-fixer:check` / `:fix`), scoped to
  `Classes/`, `Configuration/`, `Tests/` only (`.php-cs-fixer.dist.php`).
  A stale `.php-cs-fixer.php-2` in the repo root is not the active config.
- `composer.lock` covers TYPO3 13; `composer.lock.v12` exists for TYPO3 12.4
  testing.

## Documentation

- Sphinx/reST under `Documentation/`; `composer docs:build` (Docker) renders
  to `Documentation-GENERATED-temp/`.
