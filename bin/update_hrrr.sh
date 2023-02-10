#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="hrrr"
HRRR_DIR=${DATA_DIR}/hrrr
FILENAME='hrrr.t00z.wrfsfcf'
HRRR_GRID=${HRRR_DIR}/hrrr_grid
DATASETS=('APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WIND' 'DSWRF') 
DERIVED=(0 0 0 0 1 0 0) #is the dataset downloaded, or derived from other variables?
FUNCTION=('' '' '' '' 'derive_wdir' '' '') 
LEVELS=('surface' '2_m_above_ground' 'entire_atmosphere' '2_m_above_ground' '10_m_above_ground' '10_m_above_ground' 'surface') 

counter=0 

#NOMADS setup:
NOMADS_URL="https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl"
SUBREGION='subregion=&leftlon=-140&rightlon=-60&toplat=53&bottomlat=22'
#get latest forecast run:
FORECAST=`curl -s -l https://nomads.ncep.noaa.gov/pub/data/nccf/com/hrrr/prod/|cut -d '"' -f 2|cut -d '/' -f 1|grep 'hrrr\.'|tail -n 1`
#END NOMADS Setup

#GDAL exports:
GEOTIFF_BOUNDS='-2699020.247 1588193.877 2697979.753 -1588806.123'
HRRR_PROJ='+proj=lcc +lat_1=38.5 +lat_2=38.5 +lat_0=38.5 +lon_0=-97.5 +x_0=0 +y_0=0 +a=6371229 +b=6371229 +units=m +no_defs '

function derive_wdir {
   LEVEL='10_m_above_ground'

   for h in `seq -w 00 1 36`
   do
      # Get UGRD and VGRD for this hour:  
      wget -q "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVEL}=on&var_UGRD=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
		-O ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2;
      wget -q "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVEL}=on&var_VGRD=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
		-O ${HRRR_DIR}/VGRD/${FILENAME}${h}.grib2;
      #Derive WDIR:
      cdo -s -O -P 4 -invertlat -expr,'10wdir=((10u<0)) ? 360+10u:10u;' -mulc,57.3 -atan2 -mulc,-1 \
	      ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2 -mulc,-1 \
	      ${HRRR_DIR}/VGRD/${FILENAME}${h}.grib2 \
	      ${HRRR_DIR}/WDIR/${FILENAME}${h}.grib2
      t=`cdo -s showtimestamp -seltimestep,1 ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2`
      date=`date  -d $t +'%Y%m%d%H%M'` 
      gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -a_ullr ${GEOTIFF_BOUNDS} -a_srs "${HRRR_PROJ}" \
	      -b 1 ${HRRR_DIR}/WDIR/${FILENAME}${h}.grib2 \
	      ${HRRR_DIR}/WDIR/${date}.tif
      #clean up grib files:
      rm ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2 \
	      ${HRRR_DIR}/VGRD/${FILENAME}${h}.grib2 \
	      ${HRRR_DIR}/WDIR/${FILENAME}${h}.grib2
   done
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   echo ${c}
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml"
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
   if [ ${DERIVED[$counter]} = 0 ]; then 
      for h in `seq -w 00 1 36`
      do 
         wget -q "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVELS[$counter]}=on&var_${d}=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
		-O ${FILE_DIR}/${FILENAME}${h}.grib2;
	 
         t=`cdo -s showtimestamp -seltimestep,1 ${FILE_DIR}/${FILENAME}${h}.grib2`
         date=`date -d ${t} +'%Y%m%d%H%M'` 
         gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" \
		-b 1 ${FILE_DIR}/${FILENAME}${h}.grib2 \
		${FILE_DIR}/${date}.tif
	 rm ${FILE_DIR}/${FILENAME}${h}.grib2
      done
   elif [ ${DERIVED[$counter]} = 1 ]; then #derive dataset:
      ${FUNCTION[counter]} ${d} #execute corresponding derive function
   fi
   
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
   rm  ${FILE_DIR}/tif/*.tif*
   find ${FILE_DIR} -empty -type f -delete ;
#2. Move new granules in place:
   mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
#3.Re-index mosaic:
   find ${FILE_DIR}/tif -name '*.tif' -exec \
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" -d "file://"{}  \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic" \;
done
