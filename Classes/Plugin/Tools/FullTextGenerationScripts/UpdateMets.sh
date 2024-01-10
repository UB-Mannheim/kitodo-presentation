#!/bin/bash

### Update METS XML with given ALTO file ###
# This script provides an uniform way to update local METS XML files with new generated ALTO files

set -euo pipefail # exit on: error, undefined variable, pipefail

# Paramaters:
while [ $# -gt 0 ] ; do
  case $1 in
  --pageId)       pageId="$2" ;;     # Page ID (eg. log59088_1)
  --pageNum)      pageNum="$2" ;;    # Page number (eg. 1)
  --url)          url="$2" ;;        # Alto URL (eg. http://localhost/fileadmin/fulltextFolder//URN/nbn/de/bsz/180/digosi/30/tesseract-basic/log59088_1.xml)
  --outputPath)   outputPath="$2" ;; # Fulltextfile path (eg. /var/www/typo3/public/fileadmin/fulltextfolder/URN/nbn/de/bsz/180/digosi/30/tesseract-basic/log59088_1.xml)
  --ocrEngine)    ocrEngine="$2" ;;  # OCR-Engine (eg. /var/www/typo3/public/typo3conf/ext/dlf/Classes/Plugin/Tools/FullTextGenerationScripts/tesseract-basic.sh)
  --ocrIndexMets) ocrIndexMets="$2" ;;  # Index METS XML with updated METS XML (1|0)
  esac
  shift
done

# UPDATE METS:

# Extract some values from parameters:
docLocalId=$(rev <<< "$pageId" | cut -d _ -f 2- | rev) # (eg. log_59088_1 -> log_59088)
#pageNum=$(rev <<< "$pageId" | cut -d _ -f 1 | rev) # (eg. log_59088_1 -> 1)
outputFolder=$(rev <<< "$outputPath" | cut -d / -f 2- | rev) # (eg. /var/www/typo3/public/fileadmin/fulltextfolder/URN/nbn/de/bsz/180/digosi/30/tesseract-basic)
ocrEngine=$(rev <<< "$ocrEngine" | cut -d '/' -f 1 | cut -d '.' -f 2- | rev) # (eg. tesseract-basic)
metsUrl=$(rev <<< "$url" | cut -d / -f 2- | rev)"/$docLocalId.xml"

cd $outputFolder
# Check if lock file exists
while [ -f "lock_file" ]; do
    sleep 1
done
touch lock_file
mv $docLocalId.xml $docLocalId.xml.backup # Backup METS
cp $docLocalId.xml.backup mets.xml

# Check if METS-data is wrapped in an OAI node:
set +euo pipefail # unset error exits
grep -qzo '<OAI-PMH.*>.*</OAI-PMH>' mets.xml
oai=$?
set -euo pipefail # re set error exits
if [ $oai ] ; then
  # Extract the inner mets node from the OAI wrapper, make it valid xml and pretty print it:
    # xmlstarlet sel -t -c "//mets:mets" mets.xml > mets_tmp1.xml
    # echo '<?xml version="1.0" encoding="utf-8"?>' | cat - mets_tmp1.xml > mets_tmp2.xml
    # xmllint --format mets_tmp2.xml
  (echo '<?xml version="1.0" encoding="utf-8"?>' && xmlstarlet sel -t -c "//mets:mets" mets.xml) | xmllint --format - > mets_tmp.xml
  mv mets_tmp.xml mets.xml
fi

# Check if there is already a FULLTEXT section for the given pageId:
# 1. Get all FILEIDs from structMap for given page number:
physID=$(xmlstarlet sel -N mets="http://www.loc.gov/METS/" -t -v "//mets:div[@ORDER='$pageNum']/@ID" mets.xml)
fileIdList=($(xmlstarlet sel -N mets="http://www.loc.gov/METS/" -t -v '//mets:structMap[@TYPE="PHYSICAL"]/mets:div/mets:div[@ID="'$physID'"]/mets:fptr/@FILEID' -n mets.xml ));
# 2. Check if there is already a FULLTEXT section for the given fileId:
updated=0 # Flag to check if METS was updated
for fileId in "${fileIdList[@]}"; do
  if [[ -n $(xmlstarlet sel -N mets="http://www.loc.gov/METS/" -t -v '//mets:fileSec/mets:fileGrp[@USE="FULLTEXT"]/mets:file[@ID="'$fileId'"]/mets:FLocat/@xlink:href' -n mets.xml) ]] ; then
    updated=1 # Set flag to 1

    # Update METS by updating existing elements with given ALTO file:
    ocrd --log-level INFO workspace add --force --file-grp FULLTEXT --file-id "$fileId" --page-id="$physID" --mimetype text/xml "$url"
    xmlstarlet ed -L -N mets="http://www.loc.gov/METS/" -u "//mets:file[@ID='$fileId']/@CREATED" -v "$(date +%Y-%m-%dT%H:%M:%S%z)" -i "//mets:file[@ID='$fileId'][not(@CREATED)]" -t attr -n "CREATED" -v "$(date +%Y-%m-%dT%H:%M:%S%z)" mets.xml  # Add/Update date attribute to file node
    xmlstarlet ed -L -N mets="http://www.loc.gov/METS/" -u "//mets:file[@ID='$fileId']/@SOFTWARE" -v "DFG-Viewer-OCR-On-Demand-$ocrEngine" -i "//mets:file[@ID='$fileId'][not(@SOFTWARE)]" -t attr -n "SOFTWARE" -v "DFG-Viewer-OCR-On-Demand-$ocrEngine" mets.xml  # Add OCR-ENGINE attribute to file node
  fi
done

if [[ $updated == 0 ]]; then # No FULLTEXT section for fileId
  # Update METS by adding given ALTO file:
  ocrd --log-level INFO workspace add --force --file-grp FULLTEXT --file-id "fulltext-$pageId" --page-id="$physID" --mimetype text/xml "$url"
  xmlstarlet ed -L -N mets="http://www.loc.gov/METS/" -a "//mets:file[@ID='fulltext-$pageId']" -t attr -n "CREATED" -v "$(date +%Y-%m-%dT%H:%M:%S%z)" mets.xml # Add Date attribute to file node
  xmlstarlet ed -L -N mets="http://www.loc.gov/METS/" -a "//mets:file[@ID='fulltext-$pageId']" -t attr -n "SOFTWARE" -v "DFG-Viewer-OCR-On-Demand-$ocrEngine" mets.xml # Add OCR-ENGINE attribute to file node
  # ocrd workspace update-page --order "$pageNum" "$physID" # Update physical structMap if needed
fi

# Validate METS:
#apt -y install libxml2-utils
#xmllint --noout --schema http://www.loc.gov/standards/mets/mets.xsd mets.xml

rm lock_file
mv mets.xml $docLocalId.xml

# Index METS:
if [ "$ocrIndexMets" == "1" ]; then
  /var/www/typo3/vendor/bin/typo3 kitodo:index -d $metsUrl -p 3 -s dlf # TODO: do not use absolute path
fi
