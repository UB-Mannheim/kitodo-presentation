#!/bin/bash

VERSION="7.2.2"

wget -O ol.zip "https://github.com/openlayers/openlayers/releases/download/v$VERSION/v$VERSION-package.zip"
unzip -p ol.zip "v$VERSION-package/dist/ol.js" > openlayers.js
unzip -p ol.zip "v$VERSION-package/ol.css" > openlayers.css
unzip -p ol.zip "v$VERSION-package/ol.js.map" > openlayers.js.map
rm ol.zip
