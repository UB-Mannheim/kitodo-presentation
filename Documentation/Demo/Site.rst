.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-site:

****
Site
****

The generated site is a single front page (plus a few subpages) that frames the
individual viewer plugins in labelled boxes and offers a floating **style
selector** to switch the whole viewer look at runtime.

Root page (viewer)
==================

The root page shows the viewer scaffold:

* a form to open a document by METS / IIIF URL (pre-filled with the local
  sample),
* an **Examples** dropdown to load one of the built-in sample documents,
* the viewer itself, split into the individual plugins:

  .. list-table::
     :header-rows: 1
     :widths: 35 65

     * - Plugin
       - What it renders
     * - ``dlf_pageview``
       - the OpenLayers map / page image
     * - ``dlf_navigation``
       - page controls (first, back, page number, forward, last, double page)
     * - ``dlf_pagegrid``
       - thumbnail strip of the pages
     * - ``dlf_metadata``
       - the document's metadata
     * - ``dlf_tableofcontents``
       - the structure / table of contents
     * - ``dlf_calendar``
       - the newspaper year / day overview
     * - ``dlf_toolbox``
       - the toolbox (zoom, rotation, fulltext, downloads, 3D, score, ...)
     * - ``dlf_mediaplayer``
       - audio / video player (when present)
     * - ``dlf_embedded3dviewer``
       - 3D model viewer (when present)
     * - ``dlf_multiview``
       - the multi-document grid

All of these plugins read the same global :code:`tx_dlf[id]` /
:code:`tx_dlf[page]` request parameters, so they can render even without Solr
or with the image host unreachable.

Subpages
========

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Path
     - Content
   * - :code:`/oai`
     - A raw OAI-PMH endpoint (``dlf_oaipmh``), served as XML.
   * - :code:`/validation`
     - The ``dlf_validationform`` plugin: validate a METS / IIIF / any XML
       document URL against the configured schemas.
   * - :code:`/search`
     - The ``dlf_search`` plugin, backed by the emulated Apache Solr (see
       :ref:`demo-search`).

Multi-View
==========

The root page can be switched between the single-document viewer and the
multi-document grid. The two are mutually exclusive views of the same page,
selected by the :code:`tx_dlf[multiview]` request parameter. When it is set,
the :code:`dlf_multiview` grid (a draggable set of iframes, each embedding the
page viewer for one document) is rendered instead of the single viewer. The
toolbox **Add document** tool (:code:`multiViewAddSourceTool`) is what normally
adds the current document to the grid. See the :ref:`Multi View <multiview>`
plugin chapter for the plugin itself.
