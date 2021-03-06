#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env
export OGR_TRUNCATE=YES
WORKSPACE="firms"
FIRMS_DIR=${DATA_DIR}/firms
SHAPEFILES=(
	#MODIS Aqua and Terra satellites:
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Global_24h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Global_48h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Global_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_USA_contiguous_and_Hawaii_24h.zip'  
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_USA_contiguous_and_Hawaii_48h.zip' 
        #'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_USA_contiguous_and_Hawaii_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Alaska_24h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Alaska_48h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/c6/shapes/zips/MODIS_C6_Alaska_7d.zip'
	#SUOMI satellite:
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Global_24h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Global_48h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Global_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_USA_contiguous_and_Hawaii_24h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_USA_contiguous_and_Hawaii_48h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_USA_contiguous_and_Hawaii_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Alaska_24h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Alaska_48h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/suomi-npp-viirs-c2/shapes/zips/SUOMI_VIIRS_C2_Alaska_7d.zip'
	#NOAA-20 satellite:
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Global_24h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Global_48h.zip'
	'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Global_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_USA_contiguous_and_Hawaii_24h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_USA_contiguous_and_Hawaii_48h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_USA_contiguous_and_Hawaii_7d.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Alaska_24h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Alaska_48h.zip'
	#'https://firms.modaps.eosdis.nasa.gov/data/active_fire/noaa-20-viirs-c2/shapes/zips/J1_VIIRS_C2_Alaska_7d.zip'
	)   
for s in ${SHAPEFILES[@]}
do 
#1. Download archive:
   ZIPFILE=`echo $s|cut -d '/' -f 9`
   wget -q  -N -nd -nH -O ${FIRMS_DIR}/${ZIPFILE}  $s
   name=`basename ${ZIPFILE} .zip`;
   tblname=`echo ${name}|awk '{print tolower($0)}'`
   echo `date && md5sum ${FIRMS_DIR}/$ZIPFILE` >>${FIRMS_DIR}/change_tracking.log
   unzip -qq -e -o ${FIRMS_DIR}/${ZIPFILE} -d ${FIRMS_DIR} 
   export OGR_TRUNCATE=YES
   ogr2ogr -f PostgreSQL \
	   -a_srs EPSG:4326 \
	   PG:"host=localhost user=docker password=docker dbname=wfas schemas=firms port=7777" \
	   -clipsrc -180 15 -50 75 \
	   ${FIRMS_DIR}/${name}.shp ${name}
   export OGR_TRUNCATE=NO
   ogr2ogr -f PostgreSQL \
	   -a_srs EPSG:4326 \
	   PG:"host=localhost user=docker password=docker dbname=wfas schemas=firms port=7777" \
	   -clipsrc -70 -23 -57 10 \
	   ${FIRMS_DIR}/${name}.shp ${name}
   ogrinfo PG:"host=localhost user=docker password=docker dbname=wfas schemas=firms port=7777" \
	   -sql "REINDEX table firms."${tblname}
done
rm -rf ${FIRMS_DIR}/*.zip
#md5sum ${FIRMS_DIR}/*.{cpg,dbf,prj,qix,shp,shx} >>${FIRMS_DIR}/change_tracking.log
