#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="star"
STAR_DIR=${DATA_DIR}/star
STAR_FTP='https://www.star.nesdis.noaa.gov/pub/corp/scsb/wguo/data/Blended_VH_4km/geo_TIFF/'
DATASETS=('SMN')
# get data in YYYYWWW format:
#DATE=`date -d "-1 week" +%Y0%W`
DATE=`date +%Y0%W`
PATTERNS=("VHP.G04.C07.npp.P${DATE}.SM.SMN.tif")
counter=0

function get_remote_file {
   if curl -s -I "${STAR_FTP}/${1}" ; then
      echo "Getting remote file.."
      curl -s "${STAR_FTP}/${1}" -o ${FILE_DIR}/${1}
   fi
}

function transform_file {
   if [ -f ${1} ] ; then
	gdal_translate -q -of GTiff ${GEOTIFF_OPTS} ${1} ${1}.new  
	gdaladdo -q --config COMPRESS_OVERVIEW DEFLATE ${1}.new 2 4 8
   fi
}

#loop over STAR datasets:
for d in ${DATASETS[@]}
do 
   #STAR files local storage locations:
   FILE_DIR=${STAR_DIR}/${d}/tif

   #Sync to the most current STAR FTP archive
   
   if [ ! -f ${FILE_DIR}/${PATTERNS[${counter}]}.new ] ; then
	   echo "File ${PATTERNS[${counter}]}.new doesn't exists"
	   get_remote_file ${PATTERNS[${counter}]}
	   transform_file ${FILE_DIR}/${PATTERNS[${counter}]}
	   rm ${FILE_DIR}/${PATTERNS[${counter}]}
	   #add file to mosaic:
	   echo ${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic
           curl -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XPOST \
		-H "Content-type: text/plain" -d "file://"${FILE_DIR}/${PATTERNS[${counter}]}.new \
	       	"${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic"
   fi
   (( counter++ ))
done

