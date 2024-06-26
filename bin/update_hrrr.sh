#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="hrrr"
HRRR_DIR=${DATA_DIR}/hrrr
FILENAME='hrrr.t00z.wrfsfcf'
HRRR_GRID=${HRRR_DIR}/hrrr_grid
DATASETS=('APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WIND' 'DSWRF') 
DERIVED=(1 0 0 0 1 0 0) #is the dataset downloaded, or derived from other variables?
FUNCTION=('derive_precip' '' '' '' 'derive_wdir' '' '') 
LEVELS=('surface' '2_m_above_ground' 'entire_atmosphere' '2_m_above_ground' '10_m_above_ground' '10_m_above_ground' 'surface') 

counter=0 

#NOMADS setup:
NOMADS_URL="https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl"
SUBREGION='subregion=&leftlon=-140&rightlon=-60&toplat=53&bottomlat=22'
#get latest forecast run:
FORECAST=`curl -s -l https://nomads.ncep.noaa.gov/pub/data/nccf/com/hrrr/prod/|cut -d '"' -f 2|cut -d '/' -f 1|grep 'hrrr\.'|tail -n 1`
#build a filter to delete granules from previous forecast
#(but retain first 24 hours)
#and granules older than 6 weeks:
#also, add 1 hour to start of forecast,
#because APCP for F00 is all zeroes:
FORECAST_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo ${FORECAST}|cut -d '.' -f 2\`+'1 hours'`
SIX_WEEKS_AGO=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo ${FORECAST}|cut -d '.' -f 2\`-'6 weeks'`
filter="(time%20LT%20'${SIX_WEEKS_AGO}'%20OR%20time%20GTE%20'${FORECAST_START}')"
#END NOMADS Setup

#GDAL exports:
GEOTIFF_BOUNDS='-2699020.247 1588193.877 2697979.753 -1588806.123'
HRRR_PROJ='+proj=lcc +lat_1=38.5 +lat_2=38.5 +lat_0=38.5 +lon_0=-97.5 +x_0=0 +y_0=0 +a=6371229 +b=6371229 +units=m +no_defs '

function derive_wdir {
   LEVEL='10_m_above_ground'
   h=${1}
   date=${2}
   # UGRD and VGRD for this hour:  
   REMOTE_FILE="${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVEL}=on&var_UGRD=on&var_VGRD=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus"
   ${GDAL_PATH}/gdal_translate -q -of GTiff -ot Float32 \
         ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" \
	 ${REMOTE_FILE} \
         ${HRRR_DIR}/WDIR/${date}_uv.tif
   #Derive WDIR:
   ${GDAL_PATH}/gdal_calc.py --format=GTiff \
	   -A ${HRRR_DIR}/WDIR/${date}_uv.tif --A_band=1 \
	   -B ${HRRR_DIR}/WDIR/${date}_uv.tif --B_band=2 \
	   --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
	   --calc='where(57.3*arctan2(-1*A,-1*B)<0,360+(57.3*arctan2(-1*A,-1*B)),57.3*arctan2(-1*A,-1*B))' \
	   --outfile=${HRRR_DIR}/WDIR/${date}.tif
   rm ${HRRR_DIR}/WDIR/${date}_uv.tif
}

function derive_precip {
   LEVEL=${LEVELS[0]}
   h=${1}
   date=${2}
  [ $h -lt 2  ] && band=1 || band=2
      ${GDAL_PATH}/gdal_translate -q -of GTiff -ot Float32 \
	 ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" \
         -b ${band} \
	 "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVEL}=on&var_APCP=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
         ${HRRR_DIR}/APCP/${date}.tif
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   TO_REMOVE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml?filter=${filter}" \
	      |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
	   for g in ${TO_REMOVE[@]}
	   do
	   	curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
			"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml?filter=location='${g}'"
		rm -f ${g} ${g}.aux.xml
	   done
	   unset g
	done
}

#Download HRRR datasets
#and derive GTiff files:
for d in ${DATASETS[@]}
do 
   #HRRR files local storage locations:
   FILE_DIR=${HRRR_DIR}/${d}
   #Sync to the most current HRRR forecast run at 00
   #Unless we have a derived dataset, 
   #in which case we calculate it:
#1. If dataset is not derived, get data
   for h in `seq -w 01 1 36`
   do 
      date=`date --date=\`echo ${FORECAST}|cut -d '.' -f 2\`+"${h} hours" +'%Y%m%d%H%M'`
      if [ ${DERIVED[$counter]} = 0 ]; then 
         ${GDAL_PATH}/gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" \
		-b 1 "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVELS[$counter]}=on&var_${d}=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
		${FILE_DIR}/${date}.tif
      elif [ ${DERIVED[$counter]} = 1 ]; then #derive dataset:
         ${FUNCTION[counter]} ${h} ${date} #execute corresponding derive function
      fi
   done
   (( counter++ ))
done

#Files are downloaded 
#and new GTiff granules derived 
#in previous loop.
#Now update mosaics:
for d in ${DATASETS[@]}
do 
#1. Clear old granules from Geoserver's catalog and file system:
   #HRRR files local storage locations:
   FILE_DIR=${HRRR_DIR}/${d}
   #remove granules from mosaic catalog:
   remove_files_from_mosaic ${d}
   #remove old granules from system:
   find ${FILE_DIR} -empty -type f -delete ;
#2. Move new granules in place:
   mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
   rm ${FILE_DIR}/tif/*.tif.aux.xml
#3.Re-index mosaic:
   find ${FILE_DIR}/tif -name '*.tif' -exec \
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" -d "file://"{}  \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic" \;
done
