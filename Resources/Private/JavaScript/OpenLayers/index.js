// @ts-check
//
// Webpack entry for the PageView's OpenLayers dependency.
//
// PageView is written against the global `ol` namespace (ol.Map,
// ol.source.IIIF, ol.interaction.DragZoom, ...) rather than ES module
// imports, so this entry imports the individual `ol` ES modules the
// PageView actually uses and re-exposes them as `window.ol`.
//
// Because only the used modules are imported, webpack tree-shakes the
// bundle down to those modules instead of shipping OpenLayers' full
// build. The OpenLayers version is driven by the `ol` npm dependency
// (see Build/package.json). If the PageView starts using a further
// OpenLayers API, add it to the imports below.

import 'ol/ol.css';

import Map from 'ol/Map.js';
import View from 'ol/View.js';
import Feature from 'ol/Feature.js';

import {Control, MousePosition, OverviewMap, Zoom} from 'ol/control.js';
import {
  DragBox,
  DragPan,
  DragRotate,
  DragRotateAndZoom,
  DragZoom,
  Draw,
  KeyboardPan,
  KeyboardZoom,
  MouseWheelZoom,
  PinchRotate,
  PinchZoom,
  Pointer,
} from 'ol/interaction.js';
import {Image, Layer, Tile, Vector} from 'ol/layer.js';
import {IIIF, ImageStatic, Vector as VectorSource, Zoomify} from 'ol/source.js';
import {Fill, Stroke, Style} from 'ol/style.js';
import {Polygon} from 'ol/geom.js';
import {Projection} from 'ol/proj.js';
import {IIIFInfo} from 'ol/format.js';
import {
  buffer,
  containsCoordinate,
  createEmpty,
  extend,
  getCenter,
  getHeight,
  getIntersection,
  getWidth,
} from 'ol/extent.js';
import {createStringXY} from 'ol/coordinate.js';
import {composeCssTransform} from 'ol/transform.js';
import {noModifierKeys} from 'ol/events/condition.js';

window.ol = {
  Map,
  View,
  Feature,
  control: {
    Control,
    MousePosition,
    OverviewMap,
    Zoom,
  },
  interaction: {
    DragBox,
    DragPan,
    DragRotate,
    DragRotateAndZoom,
    DragZoom,
    Draw,
    KeyboardPan,
    KeyboardZoom,
    MouseWheelZoom,
    PinchRotate,
    PinchZoom,
    Pointer,
  },
  layer: {
    Image,
    Layer,
    Tile,
    Vector,
  },
  source: {
    IIIF,
    ImageStatic,
    Vector: VectorSource,
    Zoomify,
  },
  style: {
    Fill,
    Stroke,
    Style,
  },
  geom: {
    Polygon,
  },
  proj: {
    Projection,
  },
  format: {
    IIIFInfo,
  },
  extent: {
    buffer,
    containsCoordinate,
    createEmpty,
    extend,
    getCenter,
    getHeight,
    getIntersection,
    getWidth,
  },
  coordinate: {
    createStringXY,
  },
  transform: {
    composeCssTransform,
  },
  events: {
    condition: {
      noModifierKeys,
    },
  },
};
