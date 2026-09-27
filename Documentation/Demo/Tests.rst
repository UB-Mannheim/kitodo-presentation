.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-tests:

*****
Tests
*****

The demo branch adds a few test helpers that guard the demo layout and prove
the normal test suite needs no network access.

Viewer layout regression tests
==============================

Both tests run in the npm project under :file:`Build/` (Node version from
:file:`Build/.nvmrc`):

.. code-block:: bash

   npm run -C Build test:demo        # both
   npm run -C Build test:layout      # navigation-row layout
   npm run -C Build test:fullscreen  # fullscreen map height

They render the real stylesheets and scripts in headless Chrome and assert:

* **``test:layout``** (:file:`Build/Demo/test-nav-layout.mjs`): in the
  kiosk-fullscreen layout the navigation row stays on one line and the fixed
  style-selector widget does not overlap the navigation or the toolbox frame.
  A native ``<select>`` sizes itself to its widest option, so long page labels
  are the shape that makes the page pill overflow the sidebar and wrap.
* **``test:fullscreen``** (:file:`Build/Demo/test-fullscreen-map-height.mjs`):
  it loads the real :file:`PageView.js` and replays "page reloaded while in
  fullscreen, then the user leaves fullscreen", asserting the map container
  keeps a non-zero height (leaving fullscreen must not collapse the map to
  0px and hide the page image).

Both exit non-zero on failure and skip (exit 0) if no Chrome/Chromium is
available (override the binary with the :code:`$CHROME` environment variable).
Run them before committing changes to :file:`Build/Demo/styles/`,
:file:`Build/Demo/assets/` or :file:`Resources/Public/JavaScript/PageView/`.

Offline test runner
===================

:file:`Build/Test/runOfflineTests.sh` runs the unit and functional suites with
the machine's network disabled, to prove they need no external connection. It
uses the already-installed :file:`vendor/` directory and the Docker images from
:file:`Build/Test/docker-compose.yml` (no pulls, no composer):

.. code-block:: bash

   Build/Test/runOfflineTests.sh                  # PHP 8.4 (default)
   PHP_VERSION=8.2 Build/Test/runOfflineTests.sh  # PHP 8.2
   PHP_VERSION=8.5 Build/Test/runOfflineTests.sh  # PHP 8.5

When Docker is provided by Podman (e.g. on macOS) two temporary local
workarounds are applied to :file:`Build/Test/docker-compose.yml` (Podman cannot
resolve :code:`host-gateway` and does not support :code:`links:`); the file is
restored afterwards in all cases. The full output is written to a temporary
log file whose location is printed at the end; the exit code is 0 only if both
suites passed.
