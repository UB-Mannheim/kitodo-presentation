.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-themes:

******
Themes
******

.. caution:: The demo themes exist only on the demo branch, not on
   :code:`kitodo/main`.

The demo viewer is theme-able. A **style selector** in the demo page switches
the whole viewer look at runtime, and a **Dark** checkbox toggles dark mode
for themes that support it.

How themes are laid out
=======================

* The available themes are the **subdirectories** of :file:`Build/Demo/styles/`.
  Each one must contain its main stylesheet :file:`<name>.css` and may carry
  further assets (images, scripts, ...) alongside it. Add a new directory there
  and it is picked up automatically.
* The styles are **copied into the site once at setup time**, not served from
  :file:`Build/Demo/`. Editing a theme stylesheet therefore does not reach an
  already-built site — re-run the setup (or copy the file into
  :file:`<site>/kitodo-demo/`) to see a change.
* The active stylesheet is **not** a TYPO3 :typoscript:`includeCSS` (the TYPO3
  asset pipeline concatenates those into a single :file:`merged-*.css`, which a
  runtime link swap could not address). Instead the demo page's script manages
  its own :code:`<link id="dlf-demo-css">` and retargets it at
  :code:`kitodo-demo/<name>/<name>.css` when the selector changes.
* The choice is remembered in :code:`localStorage`, so it survives the full
  page reloads that viewer navigation triggers. The :code:`--style` option is
  only the default for a first visit.

.. _aurora-theme:

The aurora theme
================

:code:`aurora` is the default and the most complete theme. It is a self-contained
design that styles the whole viewer (map, navigation, page grid, metadata,
toolbox, table of contents, calendar) and provides:

* a **dark mode** (re-declared design tokens for
  :code:`:root[data-theme="dark"]`, toggled by the demo page's Dark checkbox);
* a **kiosk fullscreen layout** for the :ref:`demo-kiosk-fullscreen`, including
  the side-by-side fulltext pane;
* a layout where the navigation row stays on one line and the fixed style
  selector does not overlap the navigation or the toolbox.

Other themes
============

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Theme
     - Notes
   * - :code:`boxes`
     - A boxy variant. No dark mode.
   * - :code:`magazine`
     - A magazine-style variant. No dark mode.
   * - :code:`default`
     - A deliberate no-op: the unstyled baseline, useful as a reference.

.. note::

   :code:`Build/Demo/assets/` holds helper CSS and JavaScript (e.g.
   :file:`demo-widgets.css`) that is copied alongside the styles but is **not**
   a switchable theme.
