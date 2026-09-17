# AGENTS.md

Kitodo.Presentation: a TYPO3 extension (extension key `dlf`, PSR-4 `Kitodo\Dlf\` → `Classes/`). PHP 8.2–8.4, TYPO3 12.4 or 13.4. Apache Solr is the search backend (not needed for unit tests).

## PHP

- Install test dependencies: `composer install-via-docker -- -t 12.4` or `-- -t 13.4`
- Unit tests (Docker): `composer test:unit`; locally: `composer test:unit:local` (or `vendor/bin/phpunit -c Build/Test/UnitTests.xml`, add `--filter <name>` for one test)
- Functional tests **only run in Docker** (need MariaDB/Solr containers): `composer test:func` or `Build/Test/runTests.sh -s functional`; `-w` for watch mode. Options: `Build/Test/runTests.sh -h`
- Fixtures for functional tests live in `Tests/Fixtures/`; use distinct, greppable 9-digit `uid`s (`rand(100000000, 999999999)`)
- Static analysis: `composer phpstan` (hardwired to `.github/phpstan_13.4.neon`; CI runs one neon per TYPO3 version, `.github/phpstan_12.4.neon` included)
- Code style: `composer php-cs-fixer:check` / `composer php-cs-fixer:fix`

## JavaScript / Webpack

- The npm project is in `Build/` (Node version from `Build/.nvmrc`): `cd Build && npm ci && npm run build|watch|test|typecheck` (jest + tsc via root `jsconfig.json`)
- JS source is `Resources/Private/JavaScript/`; the `DlfMediaPlayer` webpack entry is built from `Resources/Private/JavaScript/SlubMediaPlayer/` (name ≠ directory). Jest `moduleNameMapper` maps `lib/`, `DlfMediaPlayer/`, `SlubMediaPlayer/` to `Resources/Private/JavaScript/`
- Build outputs (`Resources/Public/JavaScript/DlfMediaPlayer/`, `Resources/Public/Css/`) are **committed to the repo by a CI bot** on push to `main`. In PRs, run the build locally to verify, but do not commit the built assets yourself

## Layout

- `Classes/` — extension code (Api, Controller, Domain, Hooks, Service, ViewHelpers, ...)
- `Configuration/` — TCA, Solr configsets, services
- `Tests/Unit`, `Tests/Functional` — mirror `Classes/` namespacing; `Build/Test/` holds PHPUnit XML + Docker setup
- `madabi/` — standalone Python metadata-analysis tool, unrelated to the extension build/tests
- `issues/` — scratch material for specific bug investigations; not part of the build

## Git

- `origin` is a personal fork; upstream is remote `kitodo` (`github.com/kitodo/kitodo-presentation`). Feature branches target `main`; older release lines are maintained on `N.x` branches (see `.github/pull.yml`)
- Commit subjects use KITODO type prefixes: `[BUGFIX]`, `[FEATURE]`, `[MAINTENANCE]`, `[TASK]`
