.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-search:

******
Search
******

.. caution:: The search page and its Solr emulator exist only on the demo
   branch, not on :code:`kitodo/main`.

The demo branch adds a **search** page (``dlf_search``) that works **without a
real Apache Solr server**. The extension talks to Solr through Solarium over
plain HTTP, so the demo ships a minimal Solr HTTP emulation that implements
just enough of the Solr JSON API for the read-only demo plugins
(``dlf_search``, ``dlf_listview``, ``dlf_collection``, ``dlf_statistics``) to
work.

How it works
============

* The emulator (:file:`Build/Demo/assets/solr-emulator.php`) is included from
  the demo's static data router (:file:`Build/Demo/assets/data-router.php`).
  Any request under the :code:`/solr/` prefix is answered with a Solr-style
  JSON response; anything else falls through to static file serving.
* It implements the endpoints the extension uses: the core status probe
  (:code:`/admin/cores?action=STATUS`, which the Solr constructor uses to
  decide the core is "ready"), the select / search requests
  (:code:`/<core>/select`) and the update endpoint
  (:code:`/<core>/update`) that the real indexer pushes documents to.
* The documents to search over are the local sample documents; they are
  "indexed" by the regular indexer into the emulator's in-memory JSON catalog.

The page
========

The :code:`/search` page renders the ``dlf_search`` form and the results.
Clicking a result opens the document in the single-document viewer on the root
page. The Solr core record and the extension's Solr connection are pointed at
the local data server running the emulator, so no external Solr is contacted.
