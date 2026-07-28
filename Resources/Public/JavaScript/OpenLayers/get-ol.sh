#!/bin/bash

VERSION="7.2.2"

wget -O ol.zip "https://github.com/openlayers/openlayers/releases/download/v$VERSION/v$VERSION-package.zip"


# Create temp dir and extract
mkdir -p temp_ol
cd temp_ol
unzip ../ol.zip

#unzip -p ol.zip "v$VERSION-package/dist/ol.js" > openlayers.js
#unzip -p ol.zip "v$VERSION-package/ol.css" > openlayers.css
#unzip -p ol.zip "v$VERSION-package/dist/ol.js.map" > openlayers.js.map

# Copy files
cp dist/ol.js ../openlayers.js
cp dist/ol.js.map ../openlayers.js.map
cp ol.css ../openlayers.css

# Cleanup
cd ..
rm -rf temp_ol ol.zip
