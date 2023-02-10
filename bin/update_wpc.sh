#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="wpc"
WPC_DIR=${DATA_DIR}/wpc
REMOTE_URL='https://ftp.wpc.ncep.noaa.gov/2p5km_qpf/'
ACCUM_PERIOD=('06' '24')

#today's date in YYYYMDD format:
today=`date +'%Y%m%d'`

#GDAL exports:
PROJ4_SRS='+proj=lcc +lat_1=25 +lat_2=25 +lat_0=25 +lon_0=-95 +x_0=0 +y_0=0 +a=6371200 +b=6371200 +units=m +no_defs'

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	IFS=$'\n' COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)

	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   encoded=$(python -c "from urllib.parse import quote; print(quote('''$c'''))")
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${encoded}/index/granules.xml"
	done
}

#Download WPC QPF datasets
#and derive GTiff files:
   
#Download WPC QPFforecast run at 00
#for the 7 days that cover
#CONUS (co) region:
for a in ${ACCUM_PERIOD[@]}
do
   QPF_DIR="${WPC_DIR}/qpf${a}"
   for h in `seq -w 0${a} ${a} 168`
   do
      FILENAME="p${a}m_${today}00f${h}.grb"
      wget -q -c "${REMOTE_URL}/${FILENAME}" \
		-O ${QPF_DIR}/grb/${FILENAME};

      t=`gdalinfo ${QPF_DIR}/grb/${FILENAME} \
	   |grep '   GRIB_VALID_TIME=' -m 1|cut -d ' ' -f 7`
      date=`date -d @${t} +'%Y%m%d%H%M'` 
      gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} ${QPF_DIR}/grb/${FILENAME} ${QPF_DIR}/${date}.tif 
      gdal_edit.py -a_srs "${PROJ4_SRS}" ${QPF_DIR}/${date}.tif
      rm ${QPF_DIR}/${date}.tif.aux.xml
   done

   #Files are downloaded 
   #and new GTiff granules derived 
   #in previous loop.
   #Now update mosaics:
   #1. Clear old granules from Geoserver's catalog and file system:
   #remove granules from mosaic catalog:
   old_IFS=$IFS
   remove_files_from_mosaic "qpf${a}"
   IFS=${old_IFS}
   #remove old granules from system:
   rm -rf ${QPF_DIR}/{grb,tif}/*
   #rm -rf ${QPF_DIR}/tif/*
   #2. Move new granules into place:
   mv ${QPF_DIR}/*.tif  -t ${QPF_DIR}/tif/
   #3.Re-index mosaic:
   find ${QPF_DIR}/tif/ -name '*.tif' -exec \
      curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" -d "file://"{}  \
         "${REST_URL}/${WORKSPACE}/coveragestores/qpf${a}/external.imagemosaic" \;
done 
