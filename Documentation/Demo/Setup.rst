.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-setup:

*********
Setup
*********

The demo is built by the script :file:`Build/Demo/setup-demo.sh` in the
:code:`demo` branch. It creates a **self-contained, runnable TYPO3 13.4 +
SQLite** site in a directory of your choice. The :code:`dlf` extension is
symlinked into the site from the current checkout, so the site always runs the
exact code of the branch you are on.

No Docker, no Apache Solr and no theme CSS are required. Instead of pointing
the viewer at a public document, the script installs a small **local sample
document** (a METS file plus three placeholder pages, thumbnails, ALTO
fulltext and per-page PDFs) and serves it on its own static HTTP port, so the
PageView viewer works end to end completely offline.

Requirements
============

* PHP 8.2 or newer (a Homebrew PHP is fine) with the extensions used by
  TYPO3.
* Composer.
* A checkout of this repository on the :code:`demo` branch.

The script pins the Composer PHP platform to 8.4.99 for you, so it also works
on machines whose Homebrew PHP is newer than the dependencies support.

Running the script
==================

.. code-block:: bash

   Build/Demo/setup-demo.sh

This creates the site in :file:`$HOME/kitodo-demo-site` and prints the URLs to
open. Run it again at any time to re-sync an existing site with the current
checkout (the script is idempotent).

Options
=======

.. t3-field-list-table::
  :header-rows: 1

 - :Option:
       Option
   :Default:
       Default
   :Description:
       Description

 - :Option:
       :code:`--dir <path>`
   :Default:
       :file:`$HOME/kitodo-demo-site`
   :Description:
       Where to create the site.

 - :Option:
       :code:`--port <n>`
   :Default:
       8090 (next free port if taken)
   :Description:
       Frontend dev-server port / base URL.

 - :Option:
       :code:`--base-url <url>`
   :Default:
       (localhost dev server)
   :Description:
       Serve the site under a public base URL instead of the localhost dev
       server (e.g. behind an Apache vhost or reverse proxy). It becomes the
       TYPO3 site base, and the web server must serve
       :file:`<dir>/public` at that URL. Not allowed together with
       :code:`--serve`.

 - :Option:
       :code:`--data-url <url>`
   :Default:
       (localhost data server)
   :Description:
       Public base URL of the sample data files (:file:`<dir>/kitodo-demo`).
       Required with :code:`--base-url` unless :code:`--no-sample` is given.

 - :Option:
       :code:`--branch <name>`
   :Default:
       current git branch
   :Description:
       :code:`dlf` branch to install.

 - :Option:
       :code:`--user <name>`
   :Default:
       :code:`admin`
   :Description:
       Backend admin username.

 - :Option:
       :code:`--password <pw>`
   :Default:
       see below
   :Description:
       Backend admin password. For localhost installs (no
       :code:`--base-url`) the default :code:`demo-Passw0rd!` is used when not
       given. For web installations (:code:`--base-url`) a random password is
       generated and printed at the end when none is given (it is stored in
       :file:`<dir>/.admin-password` and reused on re-runs).

 - :Option:
       :code:`--style <name>`
   :Default:
       :code:`aurora`
   :Description:
       Viewer theme to use. The available themes are the subdirectories of
       :file:`Build/Demo/styles/`. See :ref:`demo-themes`.

 - :Option:
       :code:`--serve`
   :Default:
       (off)
   :Description:
       Start both servers in the foreground after setup.

 - :Option:
       :code:`--no-sample`
   :Default:
       (off)
   :Description:
       Skip the local sample document. The on-page form then starts empty and
       you paste any METS / IIIF URL.

 - :Option:
       :code:`-h`, :code:`--help`
   :Default:
       -
   :Description:
       Show this help.

Workarounds baked into the setup
================================

The script applies several workarounds that a fresh install otherwise needs:

* :typoscript:`enableContentLengthHeader = 0` in the site TypoScript, so the
  PageView proxy (a non-seekable stream) is not given a bogus
  :code:`Content-Length: 0` header by the cms-frontend content-length
  middleware.
* :typoscript:`plugin.tx_dlf_metadata.settings.separator` set, because that
  setting has no default and the metadata controller crashes on multivalued
  metadata when it is null.
* The FE :code:`cacheHash.requireCacheHashPresenceParameters['tx_dlf[id]']`
  and :code:`pageNotFoundOnCHashError = 0` so a viewer request carrying
  :code:`tx_dlf[id]` renders uncached instead of 404ing on the missing cHash.
* The viewer map container height is provided by the extension itself, so no
  theme CSS is needed for the viewer to render.

A separate data server
======================

The sample data (METS, page images, thumbnails, media) is served on its own
static port, distinct from the frontend app. This is deliberate: the built-in
PHP server is single-threaded, and a request that reaches back into the same
port (the app fetching the METS and page images server-side) would deadlock it.
Keeping the data on a different port avoids that.
