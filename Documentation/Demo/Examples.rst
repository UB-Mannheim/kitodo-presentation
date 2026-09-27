.. ==================================================
.. FOR YOUR INFORMATION
.. --------------------------------------------------
.. -*- coding: utf-8 -*- with BOM.

.. include:: ../Includes.txt

.. _demo-examples:

********
Examples
********

.. caution:: The built-in example documents exist only on the demo branch,
   not on :code:`kitodo/main`.

The demo ships a set of sample documents under :file:`Build/Demo/examples/`,
installed into the site's data directory at setup time and offered through the
on-page **Examples** dropdown. Several of them are fully **offline** (served
from the local data server); the newspaper *structure* is offline but its
individual page images are fetched from the live
`digi.bib.uni-mannheim.de <https://digi.bib.uni-mannheim.de>`_.

Offline samples
===============

.. list-table::
   :header-rows: 1
   :widths: 25 75

   * - Directory
     - What it demonstrates
   * - :code:`local-sample`
     - The default document pre-filled in the on-page form: a small
       monograph (METS + MODS) with three placeholder pages, thumbnails,
       ALTO fulltext and per-page PDFs. Used for the viewer, fulltext
       search, downloads and the validation form.
   * - :code:`audio-sample`
     - An audio document (METS with an ``AUDIO`` file group) that drives the
       media player.
   * - :code:`video-sample`
     - A video document (METS with a ``VIDEO`` file group) that drives the
       media player.
   * - :code:`model3d-sample`
     - A 3D object (toplevel type :code:`object`, a glTF/GLB model in the
       :code:`DEFAULT` group) that drives the embedded 3D viewer.

Reichsanzeiger (periodical)
===========================

:file:`examples/newspaper/` holds a local METS hierarchy for the *Deutscher
Reichsanzeiger und Preussischer Staatsanzeiger* (1871-1945):

* one **anchor** document (toplevel type :code:`newspaper`) with a pointer to
  every digitized year;
* one **year** file per digitized year (1873 and 1885 are not digitized),
  each with pointers to its issues.

The anchor's year pointers reference the local year files, while the year
files' issue pointers reference the live ``digi`` issue documents. The anchor
is what drives the demo's **calendar** / periodical navigation: opened with the
anchor it lists all years, opened with a year it shows that year's day
calendar.

Live examples (digi)
====================

The Examples dropdown also offers a few live documents from
``digi.bib.uni-mannheim.de`` (e.g. the *Mannheimer Privilegien*, 1652) to show
real-world material in the viewer.
