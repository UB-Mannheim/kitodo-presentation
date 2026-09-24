// This file declares the global type made available by the OpenLayers entry
// (index.js), which assembles the `ol` namespace the PageView was written
// against. There also are @typedef declarations directly in .js files.
//
// The entry only imports the modules the PageView uses, so each namespace
// here is a Pick of exactly those members (not the full ol barrel).

interface Window {
  ol: {
    Map: typeof import('ol/Map.js').default;
    View: typeof import('ol/View.js').default;
    Feature: typeof import('ol/Feature.js').default;
    control: Pick<
      typeof import('ol/control.js'),
      'Control' | 'MousePosition' | 'OverviewMap' | 'Zoom'
    >;
    interaction: Pick<
      typeof import('ol/interaction.js'),
      | 'DragBox'
      | 'DragPan'
      | 'DragRotate'
      | 'DragRotateAndZoom'
      | 'DragZoom'
      | 'Draw'
      | 'KeyboardPan'
      | 'KeyboardZoom'
      | 'MouseWheelZoom'
      | 'PinchRotate'
      | 'PinchZoom'
      | 'Pointer'
    >;
    layer: Pick<
      typeof import('ol/layer.js'),
      'Image' | 'Layer' | 'Tile' | 'Vector'
    >;
    source: Pick<
      typeof import('ol/source.js'),
      'IIIF' | 'ImageStatic' | 'Vector' | 'Zoomify'
    >;
    style: Pick<
      typeof import('ol/style.js'),
      'Fill' | 'Stroke' | 'Style'
    >;
    geom: Pick<typeof import('ol/geom.js'), 'Polygon'>;
    proj: Pick<typeof import('ol/proj.js'), 'Projection'>;
    format: Pick<typeof import('ol/format.js'), 'IIIFInfo'>;
    extent: Pick<
      typeof import('ol/extent.js'),
      | 'buffer'
      | 'containsCoordinate'
      | 'createEmpty'
      | 'extend'
      | 'getCenter'
      | 'getHeight'
      | 'getIntersection'
      | 'getWidth'
    >;
    coordinate: Pick<typeof import('ol/coordinate.js'), 'createStringXY'>;
    transform: Pick<typeof import('ol/transform.js'), 'composeCssTransform'>;
    events: {
      condition: Pick<
        typeof import('ol/events/condition.js'),
        'noModifierKeys'
      >;
    };
  };
}
