.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-kiosk-fullscreen:

**********************
Kiosk Fullscreen Mode
**********************

.. caution:: This feature exists only on the demo branch, not on
   :code:`kitodo/main`.

The demo branch adds a **kiosk fullscreen mode** to the PageView. It is meant
for large, dedicated display screens: the viewer, the navigation and the
toolbox are laid out to fill the whole screen, and the state survives page
changes (which are full page reloads).

How it works
============

The mode is **CSS-based, not the native browser Fullscreen API**. A
:class:`.tx-dlf-fullscreen` class is toggled on a container element and the
choice is stored in :code:`sessionStorage`. A theme then styles that class to
lay out the element (e.g. the map alongside the navigation and toolbar).

Because it is a class toggle rather than the native API, it survives the full
page reloads that viewer navigation (thumbnails, page controls) triggers —
which the native Fullscreen API would not. That is what keeps the viewer in
fullscreen while the page is changed.

New settings
============

* The Page View FlexForm gains a :code:`fullscreenElementId` setting: the ID
  of the element that is toggled into fullscreen. In the demo it is set to
  :code:`main`, the common ancestor of the page view, the navigation and the
  toolbox, so fullscreening it keeps all three visible.
* The toolbox zoom cluster gains a **Fullscreen Mode** button (in
  :file:`Resources/Private/Partials/Toolbox/ZoomTool.html`) that calls
  :code:`tx_dlf_viewer.toggleFullscreen()`.

Works for media and 3D documents
================================

The class toggle does not require a map, so the mode also works for documents
without a page image (audio / video / 3D), where only the map re-fit at the
end is skipped. When leaving fullscreen, the map is re-measured before
re-fitting, so the page image does not collapse to zero height.

Fulltext in a side-by-side pane
===============================

In kiosk fullscreen the fulltext panel is not an overlay on top of the page
image but a side-by-side pane: the page view frame is laid out as a flex row,
with the map as the growing pane and the fulltext as a fixed-width second pane
to the right of the image. Activating the fulltext therefore no longer covers
the page image; the image simply gets a bit narrower, and deactivating the
fulltext returns the image to full width. This layout is provided by the
:ref:`aurora theme <demo-themes>`.
