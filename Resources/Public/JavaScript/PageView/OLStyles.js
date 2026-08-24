/**
 * (c) Kitodo. Key to digital objects e.V. <contact@kitodo.org>
 *
 * This file is part of the Kitodo and TYPO3 projects.
 *
 * @license GNU General Public License version 3 or later.
 * For the full copyright and license information, please read the
 * LICENSE.txt file that was distributed with this source code.
 */

/**
 * @namespace
 *
 * @constant
 */
dlfViewerOLStyles = {};

/**
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.defaultStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': 'rgba(204,204,204,0.8)',
            'width': 3
        }),
        'fill': new ol.style.Fill({
            'color': 'rgba(170,0,0,0.1)'
        })
    });

};

/**
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.hoverStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': 'rgba(204,204,204,0.8)',
            'width': 1
        }),
        'fill': new ol.style.Fill({
            'color': 'rgba(238,153,0,0.2)'
        })
    });

};

/**
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.invisibleStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': 'rgba(170,0,0,0)',
            'width': 1
        }),
        'fill': new ol.style.Fill({
            'color': 'transparent'
        })
    });

};

/**
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.selectStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': 'rgba(170,0,0,0.8)',
            'width': 1
        }),
        'fill': new ol.style.Fill({
            'color': 'rgba(238,153,0,0.2)'
        })
    });

};

/**
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.textlineStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': 'rgba(170,0,0,1)',
            'width': 1
        })
    });

};

/**
 * Resolve a highlight color from a CSS custom property.
 *
 * @param {string} name CSS custom property name
 * @param {string} fallback fallback color
 * @returns {string}
 *
 * @private
 */
dlfViewerOLStyles.getHighlightColor_ = function(name, fallback) {
    try {
        var color = getComputedStyle(document.body).getPropertyValue(name).trim();
        if (color) {
            return color;
        }
    } catch (e) {
        // ignore and use fallback
    }
    return fallback;
};

/**
 * Highlight style for search-in-document hits; the colors can be adjusted
 * via CSS (class based), e.g.:
 *   body.dfgviewer {
 *       --dlf-search-highlight-stroke: rgba(255,235,59,0.9);
 *       --dlf-search-highlight-fill: rgba(255,235,59,0.25);
 *       --dlf-hover-highlight-stroke: rgba(197,204,232,0.9);
 *   }
 *   def. in dfg-viewer/Resources/Private/Less/modules/fulltext.less
 *
 * @returns {ol.style.Style}
 */
dlfViewerOLStyles.wordStyle = function() {

    return new ol.style.Style({
        'stroke': new ol.style.Stroke({
            'color': dlfViewerOLStyles.getHighlightColor_('--dlf-search-highlight-stroke', 'rgba(255,235,59,0.9)'),
            'width': 2
        }),
        'fill': new ol.style.Fill({
            'color': dlfViewerOLStyles.getHighlightColor_('--dlf-search-highlight-fill', 'rgba(255,235,59,0.25)')
        })
    });

};
