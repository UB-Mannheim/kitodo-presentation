# Future work / follow-ups

Follow-ups observed while fixing the CI functional tests (branch
`ci/functional-local-mets`). None of these are required for the suite to pass —
they are the skipped test and the 77 deprecations PHPUnit currently reports.

## Skipped test

- `Tests/Unit/Format/TeiHeaderTest.php::extract()` is skipped with
  "Implement test when TeiHeader class is implemented."
  The underlying class `Classes/Format/TeiHeader.php` (`TeiHeader::extractMetadata()`)
  is a stub: it only registers an XPath namespace and extracts no metadata.
  Decide whether TEI-HEADER metadata extraction is still wanted; if so,
  implement it and the test, otherwise remove the dead class + test.

## Deprecations (functional suite, PHP 8.4 / TYPO3 13.4)

PHPUnit reports 77 deprecations. Grouped by cause, in rough order of effort /
impact:

### 1. Register plugins as `CType` instead of `list_type` (largest group)

Every DLF plugin triggers:
`Plugin subtype "list_type" has been deprecated and will be removed in
TYPO3 v14.0. Register the plugin "..." as "CType" instead. Affected extension: dlf`

For all of: `dlf_pageview`, `dlf_search`, `dlf_metadata`, `dlf_navigation`,
`dlf_tableofcontents`, `dlf_collection`, `dlf_basket`, `dlf_calendar`,
`dlf_statistics`, `dlf_oaipmh`, `dlf_feeds`, `dlf_toolbox`, `dlf_pagegrid`,
`dlf_mediaplayer`, `dlf_embedded3dviewer`, `dlf_annotation`,
`dlf_listview`, plus the capitalised `ValidationForm`, `Toolbox`, etc.

`list_type` is removed in TYPO3 v14. Register the plugins via
`Configuration/TCA/Overrides/tt_content.php` (or the new plugin registration)
using `CType` instead of the legacy `list_type`. Note
`Classes/Updates/MigrateSettings.php` already migrates existing `list_type`
records to `CType`, so backend data is handled — only the registration remains.

### 2. Migrate FlexForms to the new schema

Many `FlexFormTools did an on-the-fly migration of a flex form data structure`
warnings (one per setting: `type`, `tools`, `title`, `stylesheet`,
`sortingFacets`, `solrLimit`, `showUserDefined`, `separator`, `searchIn`,
`rootline`, `pdf*`, `paginate.itemsPerPage`, `fulltext`, `features`, etc.).

This means the forms in `Configuration/FlexForms/*.xml` are still in the old
v8/v9 schema and are upgraded at runtime. Convert them to the current schema
(v10 / `typo3/cms-fluid`) so the on-the-fly migration (and its deprecation) is
gone.

Related, in the same file set:
- `Configuration/FlexForms/Toolbox.xml:33` still sets
  `<enableMultiSelectFilterTextfield>`, a TCA setting deprecated in TYPO3 v13.
  Remove it (and the corresponding TCA key).

### 3. Replace `GeneralUtility::hmac()` with `HashService`

`GeneralUtility::hmac() is deprecated and will be removed in TYPO3 v14. Use
TYPO3\CMS\Core\Crypto\HashService instead.`

Call sites to update:
- `Classes/Middleware/PageViewProxy.php:236`
- `Classes/Middleware/SearchSuggest.php:59`
- `Classes/Controller/AbstractController.php:318`
- `Classes/Controller/SearchController.php:615`
- `Classes/Controller/PageViewController.php:249`
- Tests: `Tests/Functional/Api/PageViewProxyTest.php`, `PageViewProxyDisabledTest.php`

The HMAC values feed the proxy/search `uHash`, so keep the same salt and
algorithm when switching to `HashService`.

### 4. Modernise `ext_localconf.php`

- `ext_localconf.php:48` uses `ExtensionManagementUtility::addPageTSConfig()`
  (deprecated v13, removed v14) → move to a `Configuration/page.tsconfig` file.
- `ext_localconf.php:49` uses `<INCLUDE_TYPOSCRIPT: ...>` (deprecated v13,
  removed v14) → use `@import` in the `.tsconfig` file.

### 5. Stop using deprecated Fluid view classes in tests

`AbstractTemplateView, StandaloneView and TemplateView have been marked as
deprecated in TYPO3 v13 and will be removed in v14. Use ext:core
ViewFactoryInterface instead.`

`Tests/Functional/Controller/AbstractControllerTestCase.php` builds a
`StandaloneView` directly. Move the functional controller tests onto
`ViewFactoryInterface` so they survive v14.

## Deprecations that are framework/vendor-side (action = bump dependency)

These are not fixable in this repo's own code; track them by upgrading the
affected package:

- `Phpoaipmh\Endpoint::__construct()` and
  `Phpoaipmh\Exception\OaipmhException::__construct()` — "implicitly marking
  parameter as nullable is deprecated" (PHP 8.4). Comes from
  `vendor/caseyamcl/phpoaipmh`; fixed by upgrading the package.
- `Fluid AbstractViewHelper::renderStatic()` deprecated (removed in Fluid v5)
  and `RenderingContext::getRequest` deprecated (removed in TYPO3 v14) — from
  `vendor/typo3fluid/fluid` / `vendor/typo3/cms-fluid`, surfaced via the repo's
  custom ViewHelpers (`JsFooterViewHelper`, `StdWrapViewHelper`, …). Addressed
  by upgrading Fluid / core and, if a custom ViewHelper calls `renderStatic()`,
  rewriting it as a regular ViewHelper.

## Out of scope for the current CI fix

- Making *all* of CI air-gapped (not just the tests): `composer install` still
  needs Packagist and the Docker images still need to be pulled. The test
  suites themselves are now proven to run offline (see the offline run log).
  If air-gapped CI is a goal, this needs a dependency/image-caching strategy
  (local Packagist mirror or vendored deps + pre-pulled images) as a separate
  effort.
