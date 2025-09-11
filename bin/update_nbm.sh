#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="nbm"
NBM_DIR=${DATA_DIR}/nbm
DATASETS=('APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WIND' 'DSWRF')
DATA_TYPE=('Float32' 'Int16' 'Int16' 'Int16' 'Int16' 'Float32' 'Int16')
#Below are parameter filters in KVP format, 
#used by grib_copy to extract the appropriate band
#for each variable:
GRIB_FILTERS=(":APCP:surface:" ":RH:2 m above ground:" \
	":TCDC:surface:" ":TMP:2 m above ground:" \
	":WDIR:10 m above ground:" ":WIND:10 m above ground:" \
	":DSWRF:surface:")
#which band should be converted to tif 
#after using a filter from GRIB_FILTERS
GRIB_BANDS=(2 1 1 1 1 1 1)
REMOTE_URL='https://nomads.ncep.noaa.gov/pub/data/nccf/com/blend/prod/'

#get latest forecast run:
FORECAST=`curl -s -l ${REMOTE_URL}/|grep -oP '(?<=)blend.*?(?=/)'|sort|tail -n 1`
#Extract timestamp  in YYYY-MM-DDTHH:MM:SSZ formaat for the beginning of this forecast.
#Add one hour, because NBM files start from 01 hour, not 00:
FORECAST_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo $FORECAST|cut -d '.' -f 2\`+"1 hour"`

#re-define to use the HTTP server:
#REMOTE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/blend/prod"
#GDAL exports:
PROJ4_SRS='+proj=lcc +lat_1=25 +lat_2=25 +lat_0=25 +lon_0=-95 +x_0=0 +y_0=0 +a=6371200 +b=6371200 +units=m +no_defs'

function remove_files_from_mosaic {
	var=${1}
	RETENTION_PERIOD_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`date +%Y-%m-%dT%H:%M:%SZ\`-"${RETENTION_PERIOD}"`
   	filter="(time%20LT%20'${RETENTION_PERIOD_START}'%20OR%20time%20GTE%20'${FORECAST_START}')"
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete granules:
	   TO_DELETE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml?filter=${filter}" |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
   	   for i in ${TO_DELETE[@]}
   	   do
      	      #delete the granule from mosaic:
              curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${var}/coverages/${c}/index/granules.xml?filter=location='${i}'"
      	      #remove from file system
      	      rm -f ${i}
   	   done
	done
}

#make a directory for this forecast run:
mkdir -p ${NBM_DIR}/${FORECAST}

#Download NBM forecast run at 00
#for the 36 hours that cover
#CONUS (co) region:
FILE_DIR="${NBM_DIR}/${FORECAST}"
#for h in `seq -w 001 1 36 && seq -w 039 3 192`
for h in `seq -w 001 1 36`
do
   FILENAME="blend.t00z.core.f${h}.co.grib2"
   FILE_URL="${REMOTE_URL}/${FORECAST}/00/core/${FILENAME}"
   ${WFAS_BIN_DIR}/get_inv.pl "${REMOTE_URL}/${FORECAST}/00/core/${FILENAME}.idx" \
		>"${FILE_DIR}/${FILENAME}.inv"
   counter=0 
   for d in ${DATASETS[@]}
   do 
      grep "${GRIB_FILTERS[${counter}]}" <"${FILE_DIR}/${FILENAME}.inv" \
	      | ${WFAS_BIN_DIR}/get_grib.pl $FILE_URL \
	      ${FILE_DIR}/${FILENAME}.${DATASETS[${counter}]}	
      t=`${GDAL_PATH}/gdalinfo ${FILE_DIR}/${FILENAME}.${DATASETS[${counter}]} \
	      |grep '   GRIB_VALID_TIME=' -m 1|tail -n 1|cut -d '=' -f 2`
      date=`date -d @${t} +'%Y%m%d%H%M'` 
      ${GDAL_PATH}/gdal_translate -q -b ${GRIB_BANDS[${counter}]} -ot ${DATA_TYPE[${counter}]} \
	      -of GTiff ${GEOTIFF_OPTIONS}  ${FILE_DIR}/${FILENAME}.${DATASETS[${counter}]} \
	      ${NBM_DIR}/${d}/tif/${date}.tif
      ${GDAL_PATH}/gdal_edit.py -a_srs "${PROJ4_SRS}" ${NBM_DIR}/${d}/tif/${date}.tif
      sed -i 's/GRIB/GDAL/' ${NBM_DIR}/${d}/tif/${date}.tif
      rm ${NBM_DIR}/${d}/tif/${date}.tif.aux.xml
      find ${NBM_DIR}/${d} -mindepth 1 -maxdepth 1 -type d -empty -delete
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
   #the following line removes any directories other than current forecast from system:
   ##find ${MOSAIC_DIR} -depth -name ${FORECAST} -prune -o -name 'blend*' -type d -exec rm -rf {} \;
#2.Re-index mosaic:
   find ${MOSAIC_DIR}/tif -name '*.tif' -exec \
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" -d "file://"{}  \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic" \;
done
rm -rf ${NBM_DIR}/blend*
${MOUNT_DIR}/wfas/bin/netcdf_package_export.sh archive=nbm starttime="`date +'%Y-%m-%dT00:00:00Z'`"

