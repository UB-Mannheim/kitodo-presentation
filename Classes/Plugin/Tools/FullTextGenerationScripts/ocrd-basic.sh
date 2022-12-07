#!/bin/bash

### OCRD OCR generation script ###
# This script provides an uniform way to run OCR with OCRD on local or remote images

set -euo pipefail # exit on: error, undefined variable, pipefail

# Error message:
function usage() {
	echo "No parameter set"; #TODO
	exit 1;
}

# Test fuction, for manually testing the script
function test() {
	ssh ${ocrd-kitodo} wget -P /data/production-test/images/ "https://digi.bib.uni-mannheim.de/fileadmin/digi/1652998276/max/1652998276_0001.jpg" && for_production.sh --proc-id 1 --lang deu --script Fraktur "production-test"
	ssh ${ocrd-kitodo}:"/data/production-test/ocr/alto/502592915_0011.xml" "."
	exit 0;
}

# Check for parameter:
[ $# -eq 0 ] && usage # If no parameter given call usage()

# Paramaters:
while [ $# -gt 0 ] ; do
  case $1 in
  	-h | --help)		usage ;;
	--image_path)		image_path="$2" ;;		#Image path/URL
	--output_path)		output_path="$2" ;;		#Fulltextfile path
	--ocrLanguages)		ocrLanguages="$2" ;;	#Models&Languages for OCRD
	--ocrOptions)		ocrOptions="$2" ;;		#Output types
	--test)				test ;;
  esac
  shift
done

# Check for required parameters:
if [[ -z ${image_path} || -z ${output_path} || -z ${ocrLanguages} || -z ${ocrOptions} ]] ; then
	usage;
fi

# Parse URL or Path and run OCR:
regex='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]' #Regex for URL validation ( https://stackoverflow.com/a/3184819 )
if [[ (${image_path} =~ $regex) || (-f ${image_path}) ]] ; then # If image_path is a valid URL or a local file
	echo "Running OCRD-OCR: tesseract $image_path $output_path -l $ocrLanguages $ocrOptions"
	jobname="test";
	# start job:
	ssh ${ocrd-kitodo} wget -P "/data/${jobname}/images/" "${image_path}" && for_production.sh --proc-id 1 --lang deu --script Fraktur "${jobname}"
	# get fulltexts:
	scp ${ocrd-kitodo}:"/data/${jobname}/ocr/alto/${filename}.xml" "${output_path}"
	# clean dir:
	ssh ${ocrd-kitodo} rm -r "/data/${jobname}/"
	exit 0
else
	echo "File not found: ${image_path}"
	exit 2
fi