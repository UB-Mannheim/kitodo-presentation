.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt


.. _configuration:

################
Plugin Reference
################

.. contents::
    :local:
    :depth: 4

Kitodo Plugin Reference
=======================

Common Settings
---------------

.. _fluidplugins:

Fluid Template Configuration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

As of Kitodo.Presentation 4.0 the Fluid rendering engine is used. The former
marker templates for plugins are not supported anymore.

Now, all HTML markup is done in Fluid. To use different templates, you have
to overload the templates by the common TYPO3 way.

The following TypoScript defines additional paths inside an "example" extension::

   plugin.tx_dlf {
      view {
         templateRootPaths {
            10 = EXT:example/Resources/Private/Plugins/Kitodo/Templates
         }
         partialRootPaths {
            10 = EXT:example/Resources/Private/Plugins/Kitodo/Partials
         }
      }
   }

In this example, you place the customized fluid template into this file::

   EXT:example/Resources/Private/Plugins/Kitodo/Partials/Navigation/Main.html


Annotation
----------

The Annotation plugin lists, for the current page, the annotations that an
external annotation server has stored for the document. The annotations are
fetched through the IIIF Annotation API.

:typoscript:`plugin.tx_dlf_annotation.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      apiUrl
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

   :Description:
      Base URL of the IIIF annotation server that provides the annotations
      for the documents. If it is empty, no annotations are requested.


Basket
------

:typoscript:`plugin.tx_dlf_basket.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      pregeneration
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      pdfgenerate
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      pdfdownload
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      pdfprint
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      pdfparams
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      ##docId##,##startpage##,##endpage##,##startx##,##starty##,##endx##,##endy##,##rotation##

 - :Property:
      pdfparamseparator
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      `*`

 - :Property:
      basketGoToButton
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetBasket
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:


Calendar
--------

The calendar plugin may be used with newspaper and ephemeras (periodical
published media). The plugin shows itself an overview of all available
years or all issues in a calendar view of a selected year.

You can't place the plugin together with the pageview plugin on one page.
But you can use TypoScript conditions on this page to select the proper
plugin e.g by setting some specific FLUID variables.

This is an example usage of the TypoScript condition ("getDocumentType")::

    [getDocumentType({$plugin.tx_dlf.persistence.storagePid}) === 'ephemera' or getDocumentType({$plugin.tx_dlf.persistence.storagePid}) === 'newspaper']
    page.10.variables {
        isNewspaper = TEXT
        isNewspaper.value = newspaper_anchor
    }
    [END]

    [getDocumentType({$plugin.tx_dlf.persistence.storagePid}) === 'year']
    page.10.variables {
        isNewspaper = TEXT
        isNewspaper.value = newspaper_year
    }
    [END]

    [getDocumentType({$plugin.tx_dlf.persistence.storagePid}) === 'issue']
    page.10.variables {
        isNewspaper = TEXT
        isNewspaper.value = newspaper_issue
    }
    [END]

The `{$plugin.tx_dlf.persistence.storagePid}` is a TypoScript constant holding the Kitodo.Presentation storage pid.

This way, the FLUID variable "isNewspaper" is set according to the given
value. Inside the FLUID template it's possible to switch to the right plugin
now.

:typoscript:`plugin.tx_dlf_calendar.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      initialDocument
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      showEmptyYears
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      showEmptyMonths
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1


Collection
----------

The collection plugin shows one collection, all collections or selected collections. It can be used to display the list
of collections or the contents of a single collection. The plugin is configured in the TypoScript and in the FlexForm.

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_collection.settings.list.paginate`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      itemsPerPage
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      25

 - :Property:
      insertAbove
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      insertBelow
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      maximumNumberOfLinks
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      10

 - :Property:
      section
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      showResults

FlexForm Configuration
^^^^^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      collections
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      solrcore
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      showUserDefined
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      showSingle
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      showOverview
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1

 - :Property:
      showDocuments
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1

 - :Property:
      randomize
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      targetFeed
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

Embedded 3D Viewer
------------------

The embedded3dviewer plugin renders an iFrame in which the configured 3D viewer displays the model.

:typoscript:`plugin.tx_dlf_embedded3dviewer.settings.`

FlexForm Configuration
^^^^^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Description:
      Description

 - :Property:
      document
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Description:
      The URL of the XML document which contains the model.

 - :Property:
      model
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Description:
      The URL of the 3D model.

 - :Property:
      viewer
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Description:
      Override the default viewer from the extension configuration (see :ref:`Embedded 3D Viewer Configuration`) with a supported viewer (from the "dlf_3d_viewers" directory).

Feeds
-----

The feeds plugin renders a RSS 2.0 feed of last updated documents of all or a specific collection.

The following steps are necessary to activate the plugin:

a. Create a new page "Feed" with slug "feed".
b. Create an extension template on this page and include the TypoScript template of the feeds plugin.
c. Place the "Kitodo Feeds" plugin on it and configure it for your needs.

The TypoScript part is necessary to switch the page rendering to a different page object.

:typoscript:`plugin.tx_dlf_feeds.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      collections
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      excludeOtherCollections
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      library
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      limit
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      50

 - :Property:
      prependSuperiorTitle
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      title
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      description
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

List View
---------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_listview.settings.list.paginate`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
       Property
   :Data Type:
       Data type
   :Default:
       Default

 - :Property:
      itemsPerPage
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      25

 - :Property:
      insertAbove
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      insertBelow
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      maximumNumberOfLinks
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      10

 - :Property:
      section
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      showResults

FlexForm Configuration
^^^^^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      limit
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      25

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      getTitle
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      getStructurePath
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      basketButton
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetBasket
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

Media Player
------------

The MediaPlayer plugin is only active if the selected document has valid audio or video file use groups (useGroupsAudio, useGroupsVideo).

:typoscript:`plugin.tx_dlf_mediaplayer.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      excludeOther
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:
      Show only documents from the selected page.

 - :Property:
      elementId
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx-dlf-media
   :Description:
      ID value of the HTML element for the media player.

Metadata
--------

:typoscript:`plugin.tx_dlf_metadata.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      excludeOther
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:
      Show only documents from the selected page.

 - :Property:
      linkTitle
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

   :Description:

 - :Property:
      getTitle
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:

 - :Property:
      showFull
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:

 - :Property:
      rootline
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      0
   :Description:

 - :Property:
      separator
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      `#`
   :Description:

.. _multiview:

Multi View
----------

The Multi View plugin opens a grid in which several documents can be shown
side by side, each embedded in its own frame. The documents and their pages
are selected through the request parameters :code:`tx_dlf[multiview]` and
:code:`tx_dlf[multiViewSource][<n>]`. A URL is normally not assembled by hand:
the *Add Source* tool of the :ref:`Toolbox` (``multiViewAddSourceTool``)
appends the current document to the grid. The grid layout (position and size of
each frame) is created with `Gridstack <https://gridstackjs.com/>`__ and is
remembered in a cookie, so it is preserved for the current user.

.. note::

    When :code:`tx_dlf[multiview]` is set, the gridstack and Multi View
    JavaScript are loaded and the Page View plugin is expected to be embedded
    in a frame rather than rendered directly on the page. The demo site
    (see :ref:`demo-site`) combines the two plugins this way.

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_multiview.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      multiDocumentTypes
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

   :Description:
      Comma separated list of structure types for which the current document
      is expanded into its child documents and added to the grid in one step.
      Leave empty to compare independent documents side by side.

Navigation
----------

This plugin adds a navigation to the page view for navigating through the pages of a document. The navigation buttons are displayed in the order included in configuration.
Features `pagesBackward` and `pagesForward` offer adding multiple navigation buttons grouped together.

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_navigation.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Values:
      Values

 - :Property:
      features
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      By default all features are activated. The selection is stored as comma separated list.

      doublePage,pageFirst,pageBack,pageStepBack,pageSelect,pageForward,pageStepForward,pageLast,listView,measureForward,measureBack,documentBack,documentForward
   :Values:
      * documentBack
      * documentForward
      * doublePage
      * listView
      * measureBack
      * measureForward
      * pageBack
      * pageFirst
      * pageForward
      * pageLast
      * pageSelect
      * pageStepBack
      * pageStepForward
      * pagesBackward
      * pagesForward

 - :Property:
      pageStep
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      5

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

OAI-PMH
-------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_oaipmh.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      library
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      solrcore
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      limit
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      5

 - :Property:
      solrLimit
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      50000

 - :Property:
      expired
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1800

 - :Property:
      showUserDefined
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      stylesheet
   :Data Type:
      :ref:`t3tsref:data-type-resource`
   :Default:

Page Grid
---------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_pagegrid.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      paginate.itemsPerPage
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      10

 - :Property:
      placeholder
   :Data Type:
      :ref:`t3tsref:data-type-resource`
   :Default:
      (no default)
   :Description:
      Image shown instead of a thumbnail for pages that have no thumbnail.

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

Page View
---------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_pageview.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      excludeOther
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:
      Show only documents from the selected page.

 - :Property:
      features
   :Data Type:
      `t3tsref:data-type-list`
   :Default:
      (none)
   :Description:
      OpenLayers controls to create, comma separated. Valid values: ``OverviewMap``, ``ZoomPanel``.

 - :Property:
      elementId
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx-dlf-map
   :Description:
      ID value of the HTML element for the document images.

 - :Property:
      progressElementId
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx-dlf-page-progress
   :Description:
      ID value of the HTML element for the page progress bar.

 - :Property:
      useInternalProxy
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Description:
      Serve the page images through the extension's own proxy instead of
      linking to the original image URLs.

 - :Property:
      basketButton
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Description:
      Show an "add to basket" button for the current page.

 - :Property:
      basket.crop
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Description:
      Enable the cropping tool, which lets the user select a region of the
      page to add to the basket. Only available when ``basketButton`` is set.

 - :Property:
      basket.magnifier
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Description:
      Enable the magnifier, which shows a zoomed view of the page at the
      mouse location. Only available when ``basketButton`` is set.

 - :Property:
      targetBasket
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

   :Description:

 - :Property:
      multiViewType
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

   :Description:
      Optional type for the Multi-View feature, see :ref:`Multi View <multiview>`.

Search
------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_search.settings.list.paginate`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      itemsPerPage
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      25

 - :Property:
      insertAbove
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      insertBelow
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      1

 - :Property:
      maximumNumberOfLinks
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      10

 - :Property:
      section
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      showResults

FlexForm Configuration
^^^^^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      fulltext
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:

 - :Property:
      fulltextPreselect
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      datesearch
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      solrcore
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

 - :Property:
      extendedSlotCount
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      0

 - :Property:
      extendedFields
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      0

 - :Property:
      searchIn
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      collections
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      facets
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      facetCollections
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      limitFacets
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      15

 - :Property:
      resetFacets
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      sortingFacets
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      suggest
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1

 - :Property:
      showLogicalPageField
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      showSingleResult
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      targetPidPageView
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

.. _sru:

SRU Interface
-------------

The SRU plugin serves an SRU 1.2 ``searchRetrieve`` endpoint in the
``dfg-viewer/page`` record schema. It allows a
`DFG-Viewer <https://dfg-viewer.de/>`__ installation to search the fulltext
of this repository's Solr index and to deep-link into the Page View with the
search hits highlighted. Each record describes one hit physical page: the
page number, the URL of the parent METS document, the image width/height of
the page (taken from the OCR data, omitted if the page has no fulltext) and
one ``fulltexthit`` per matched OCR hit with absolute coordinates, a
thumbnail preview and a snippet.

The whole configured Solr core is searched, so the core must be indexed with
OCR fulltext (see the ``solr-ocrhighlighting`` requirement). The plugin has
to be placed on a page of its own: its static TypoScript template switches
the page rendering to raw XML output.

Activating the Plugin
^^^^^^^^^^^^^^^^^^^^^

The following steps are necessary to activate the plugin:

a. Create a new page "SRU" with a free slug (e.g. ``sru``).
b. Create a TypoScript extension template on this page and include the template "SRU Plugin Configuration".
c. Place the "Kitodo: SRU Interface" plugin on the page and select the Solr core to be searched.

A DFG-Viewer instance then points its SRU client at the URL of this page.
The client requests ``searchRetrieve`` results, for example::

    https://example.org/sru/?operation=searchRetrieve&version=1.2&startRecord=1&maximumRecords=10&recordSchema=dfg-viewer/page&query=freiburg

For every hit page, the DFG-Viewer client builds a deep link with the
standard Kitodo.Presentation request parameters: the page's METS URL
(``tx_dlf[id]``), the page number (``tx_dlf[page]``), the highlight boxes
(``tx_dlf[highlight]``) and the page image dimensions (``tx_dlf[origimage]``),
so that the viewer opens the hit page with the matches marked.

FlexForm Configuration
^^^^^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      solrcore
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      (the extension's main Solr core)
   :Description:
      The Solr core to search. If empty, the main Solr core from the
      extension configuration is used.

 - :Property:
      maximumRecords
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:
      10
   :Description:
      Default number of records per response. The client's
      ``maximumRecords`` request parameter overrides this value; the number
      of records is capped at 100.

Request Parameters
^^^^^^^^^^^^^^^^^^

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Parameter
   :Description:
      Description

 - :Property:
      operation
   :Description:
      Must be ``searchRetrieve``. Any other value results in a valid
      response with an empty record list.

 - :Property:
      query
   :Description:
      The search phrase for the indexed fulltext. An empty query results in
      an empty record list.

 - :Property:
      recordSchema
   :Description:
      Must be ``dfg-viewer/page``. Any other value results in an empty
      record list.

 - :Property:
      startRecord
   :Description:
      One-based number of the first record to return (default 1).

 - :Property:
      maximumRecords
   :Description:
      Maximum number of records to return (default: the ``maximumRecords``
      FlexForm setting, i.e. 10). The value is capped at 100.

 - :Property:
      version
   :Description:
      Accepted for compatibility (the DFG-Viewer client sends 1.2); not
      evaluated.

Record Format
^^^^^^^^^^^^^

The response is an SRU 1.2 ``searchRetrieveResponse``. Each record contains
a ``page`` element (namespace ``http://dfg-viewer.de/``) with the attributes
``id`` (the page number), and ``width``/``height`` (the page image
dimensions in the coordinate frame of the highlight boxes, omitted if the
page has no OCR data). Its children are a ``parent`` element with the
``url`` attribute (the METS document of the hit page, used for the deep
link) and one ``fulltexthit`` element per OCR hit with the attributes
``x1``, ``y1``, ``x2``, ``y2`` (absolute image coordinates) and ``preview``
(a page thumbnail). A ``fulltexthit`` contains a ``span`` element with a
snippet of the matched text. Example::

    <srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/" version="1.2">
      <srw:version>1.2</srw:version>
      <srw:numberOfRecords>1</srw:numberOfRecords>
      <srw:records>
        <srw:record>
          <srw:recordSchema>dfg-viewer/page</srw:recordSchema>
          <srw:recordPacking>xml</srw:recordPacking>
          <srw:recordData>
            <page xmlns="http://dfg-viewer.de/" id="3" width="2481" height="3508">
              <parent url="https://example.org/mets/bestandsdaten/mets.xml"/>
              <fulltexthit x1="139" y1="141" x2="230" y2="157" preview="https://example.org/iiif/.../full.jpg">
                <span>some context <span class="highlight">Freiburg</span> more context</span>
              </fulltexthit>
            </page>
          </srw:recordData>
        </srw:record>
      </srw:records>
    </srw:searchRetrieveResponse>

.. note::

    The response is intentionally emitted with the literal ``srw:`` prefix
    (``<srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/">``)
    rather than in the standard default namespace, because the DFG-Viewer
    client resolves the response with an XPath query that does not register
    the prefix.

Statistics
----------

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_statistics.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default

 - :Property:
      collections
   :Data Type:
      `t3tsref:data-type-list`
   :Default:

 - :Property:
      description
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

Table Of Contents
-----------------

Table of Contents plugin renders a table of contents for the current document. The table of contents is generated
based on the structure of the document.

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_tableofcontents.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Description:
      Description

 - :Property:
      excludeOther
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      1
   :Description:
      Show only documents from the selected page.

 - :Property:
      basketButton
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      showFull
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0

 - :Property:
      targetBasket
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      targetPid
   :Data Type:
      `t3tsref:data-type-page-id`
   :Default:

 - :Property:
      titleReplacements
   :Data Type:
      `t3tsref:data-type-list`
   :Default:
      0 {
         type = issue
         fields = type,year
      }
      1 {
         type = volume
         fields = type,volume
      }
   :Description:
      List containing types for which title should be replaced
      when the label is empty. The defined fields are used for
      replacement.

Toolbox
-------

Toolbox Plugin is a plugin which can be used to display a selection of tools for the current page. The available tools are configured in the TypoScript.

'tools' is a required property which must contain at least one of the supported tools. The plugin will only be rendered if at least one tool is configured and supported for the current page.

TypoScript Configuration
^^^^^^^^^^^^^^^^^^^^^^^^

:typoscript:`plugin.tx_dlf_toolbox.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Values:
      Values

 - :Property:
      tools
   :Data Type:
      `t3tsref:data-type-string`
   :Default:
   :Values:
      * annotationTool
      * audioVideoTool
      * fulltextDownloadTool
      * fulltextTool
      * imageDownloadTool
      * imageManipulationTool
      * modelDownloadTool
      * multiViewAddSourceTool
      * pdfDownloadTool
      * rotationTool
      * searchInDocumentTool
      * scoreTool
      * viewerSelectionTool
      * zoomTool

 - :Property:
      showAsList
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Values:
      0: show tools as single <li> elements
      1: show tools as list inside the <ul> element

 - :Property:
      solrCoreUid
   :Data Type:
      :ref:`t3tsref:data-type-integer`
   :Default:

Tools
^^^^^

All tools are rendered by the single :code:`dlf_toolbox` plugin and are
configured in the same :typoscript:`plugin.tx_dlf_toolbox.settings` block:
the :code:`tools` property selects which tools are shown (comma separated)
and the individual tool options follow as sibling properties. There is no
separate :typoscript:`plugin.tx_dlf_<tool>.` object per tool.

Audio Video Tool
~~~~~~~~~~~~~~~

This tool loads the buttons for the audio label image, equalizer and marker table.

..  code-block:: typoscript
    :caption: Example configuration for Audio Video Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = audioVideoTool
        }
    }

Fulltext Tool
~~~~~~~~~~~~~
This tool adds an activation link for fulltext to the toolbox. If no fulltext is available for the current page, a span-tag is rendered instead.

The default behavior is to show the fulltext after click on the toggle link. There is a TypoScript configuration to show the fulltext initially.

The following settings are part of :typoscript:`plugin.tx_dlf_toolbox.settings.`:

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Values:
      Values

 - :Property:
      activateFullTextInitially
   :Data Type:
      :ref:`t3tsref:data-type-boolean`
   :Default:
      0
   :Values:
      0: show fulltext after click on toggle link
      1: show fulltext on document load

 - :Property:
      fullTextScrollElement
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      (no default)

The fulltext is fetched and rendered by JavaScript into the `<div id="tx-dlf-toolbox-fulltext-selection">` of the pageview plugin.

**Please note**: To allow JavaScript fetching the fulltext, the `CORS headers <https://en.wikipedia.org/wiki/Cross-origin_resource_sharing>`_ must be configured appropriate on the providing webserver.

..  code-block:: typoscript
    :caption: Example configuration for Fulltext Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = fulltextTool
            activateFullTextInitially = 0
            fullTextScrollElement = html, body
            showAsList = 0
        }
    }

Image Tool
~~~~~~~~~~~~~~~~~~~~~~
This tool adds buttons for rotating, zooming and manipulating the image to the toolbox and display them as list of elements.

..  code-block:: typoscript
    :caption: Example configuration for Image Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = rotationTool,zoomTool,imageManipulationTool
            showAsList = 1
        }
    }

Model Download Tool
~~~~~~~~~~~~~~~~~~~

This tool makes it possible to extract the model URL from the METS file or use the provided model parameter to provide a download URL.

The following settings are part of :typoscript:`plugin.tx_dlf_toolbox.settings.`:

..  code-block:: typoscript
    :caption: Example configuration for Model Download Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = modelDownloadTool
        }
    }

Score Tool
~~~~~~~~~~

This tool extracts the score from the `SCORE` file group and visualizes the MEI score of current page using `Verovio <https://www.verovio.org/index.xhtml>`_.

The provided MIDI output of `Verovio` is played using the `html-midi-player <https://cifkao.github.io/html-midi-player/>`_

:typoscript:`plugin.tx_dlf_toolbox.settings.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Values:
      Values

 - :Property:
      midiPlayerSoundFont
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Values:
      * `default` or if the property is not set, the MIDI player will use a simple oscillator synth
      * `built-in` or if the property is empty, the built-in sound font (`https://storage.googleapis.com/magentadata/js/soundfonts/sgm_plus`) of MIDI player is used
      *  Custom URL to sound font e.g. `https://storage.googleapis.com/magentadata/js/soundfonts/sgm_plus`

..  code-block:: typoscript
    :caption: Example configuration for Score Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = scoreTool
            midiPlayerSoundFont = default
        }
    }

Search in Document Tool
~~~~~~~~~~~~~~~~~~~~~~~
This tool adds a possibility to search all appearances of the phrase in the currently displayed document.

The following settings are part of :typoscript:`plugin.tx_dlf_toolbox.settings.`:

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Default:
      Default
   :Values:
      Values

 - :Property:
      searchUrl
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:

 - :Property:
      documentIdUrlSchema
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      empty
   :Values:
      https://host.de/items/*id*/record - example value

 - :Property:
      idInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[id]

 - :Property:
      queryInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[query]

 - :Property:
      startInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[start]

 - :Property:
      pageInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[page]

 - :Property:
      highlightWordInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[highlight_word]

 - :Property:
      encryptedInputName
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Default:
      tx_dlf[encrypted]

..  code-block:: typoscript
    :caption: Example configuration for Search In Document Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = searchInDocumentTool
            idInputName = tx_dlf[id]
            pidInputName = tx_dlf[pid]
            queryInputName = tx_dlf[query]
            startInputName = tx_dlf[start]
            pageInputName = tx_dlf[page]
            highlightWordInputName = tx_dlf[highlight_word]
            encryptedInputName = tx_dlf[encrypted]
        }
    }

Viewer Selection Tool
~~~~~~~~~~~~~~~~~~~~~

This tool can display a selection list of configured 3D viewers (from the "dlf_3d_viewers" directory see :ref:`Embedded 3D Viewer Setup`) that support the current model.

The model URL is extracted from the METS file or taken from the provided model parameter. The extension of the model is extracted from this URL and compared with the supported model formats specified in the respective viewer configuration.

..  code-block:: typoscript
    :caption: Example configuration for Viewer Selection Tool

    plugin.tx_dlf_toolbox {
        settings {
            tools = viewerSelectionTool
        }
    }

.. _Plugin Validation Form:

Validation Form
---------------

The plugin renders an input field where a METS URL can be entered. After submission, the document is loaded and validated against the :ref:`DOMDocumentValidation Middleware`. For the validation to work, a corresponding configuration (see :ref:`DOMDocumentValidation Middleware Configuration`) must be present in TypoScript, and the type of this configuration must be provided to the plugin as a required parameter.

:typoscript:`plugin.tx_dlf_validationform.`

.. t3-field-list-table::
 :header-rows: 1

 - :Property:
      Property
   :Data Type:
      Data type
   :Description:
      Description

 - :Property:
      type
   :Data Type:
      :ref:`t3tsref:data-type-string`
   :Description:
      Validation configuration type for DOMDocument validation
