#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="nbm"
NBM_DIR=${DATA_DIR}/nbm
DATASETS=('APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WIND' 'DSWRF') 
#Below are parameter filters in KVP format, 
#used by grib_copy to extract the appropriate band
#for each variable:
GRIB_FILTERS=('shortName=tp,lengthOfTimeRange:=1,productDefinitionTemplateNumber=8' \
	'shortName=2r' 'shortName=tcc' 'shortName=2t' 'shortName=10wdir' \
	'shortName=10si,productDefinitionTemplateNumber=0' 'shortName=dswrf')
REMOTE_URL='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/blend/prod'

#get latest forecast run:
FORECAST=`curl -s -l ${REMOTE_URL}/|cut -d '"' -f 2|cut -d '/' -f 1|tail -n 1`

#GDAL exports:
PROJ4_SRS='+proj=lcc +lat_1=25 +lat_2=25 +lat_0=25 +lon_0=-95 +x_0=0 +y_0=0 +a=6371200 +b=6371200 +units=m +no_defs'

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml"
	done
}

#make a directory for this forecast run:
mkdir -p ${NBM_DIR}/${FORECAST}
#now for each variable:
for d in ${DATASETS[@]}
do 
   mkdir -p ${NBM_DIR}/${d}/${FORECAST}
done

#Download NBM datasets
#and derive GTiff files:
   
#Download NBM forecast run at 00
#for the 36 hours that cover
#CONUS (co) region:
FILE_DIR="${NBM_DIR}/${FORECAST}"
for h in `seq -w 001 1 36`
do
   FILENAME="blend.t00z.core.f${h}.co.grib2"
   wget -q -c "${REMOTE_URL}/${FORECAST}/00/core/${FILENAME}" \
		-O ${FILE_DIR}/${FILENAME};

   t=`gdalinfo ${FILE_DIR}/${FILENAME} \
	   |grep '   GRIB_VALID_TIME=' -m 1|cut -d ' ' -f 7`
   date=`date -d @${t} +'%Y%m%d%H%M'` 
   counter=0 
   for d in ${DATASETS[@]}
   do 
      grib_copy -w ${GRIB_FILTERS[${counter}]} ${FILE_DIR}/${FILENAME} \
	       ${FILE_DIR}/${FILENAME}.${DATASETS[${counter}]}	
      gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS}  ${FILE_DIR}/${FILENAME}.${DATASETS[${counter}]} \
	      ${NBM_DIR}/${d}/${FORECAST}/${date}.tif
      gdal_edit.py -a_srs "${PROJ4_SRS}" ${NBM_DIR}/${d}/${FORECAST}/${date}.tif
      #rm ${NBM_DIR}/${d}/${FORECAST}/${date}.tif.aux.xml
      (( counter++ ))
   done
done

#Files are downloaded 
#and new GTiff granules derived 
#in previous loop.
#Now update mosaics:
for d in ${DATASETS[@]}
do 
#1. Clear old granules from Geoserver's catalog and file system:
   #NBM files local storage locations:
   MOSAIC_DIR=${NBM_DIR}/${d}
   #remove granules from mosaic catalog:
   remove_files_from_mosaic ${d}
   #remove old granules from system:
   find ${MOSAIC_DIR} -depth -name ${FORECAST} -prune -o -name 'blend*' -type d -exec rm -rf {} \;
#2.Re-index mosaic:
   find ${MOSAIC_DIR}/${FORECAST} -name '*.tif' -exec \
	   curl -s -u admin:geoserver -H "Content-type: text/plain" -d "file://"{}  \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic" \;
done
rm -rf ${NBM_DIR}/blend*
