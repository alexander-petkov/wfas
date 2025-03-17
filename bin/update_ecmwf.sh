#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="ecmwf"
DATASETS=('2t' '2d' 'ssrd' '10u' '10v' 'tp')
BANDS=(4 5 6 2 3 1)
COVERAGESTORES=('2t' '2r' 'ssrd' 'wdir' 'wspd' 'tp')
DERIVED=(0 1 0 1 1 0) #is the coverage downloaded, or derived from other datasets?
FUNCTION=('' 'derive_rh' '' 'derive_wdir' 'derive_wspd' '')
STEPS=(`seq 0 3 144`)
ECMWF_DIR=${DATA_DIR}/${WORKSPACE}

function download_data {
	for step in ${STEPS[@]}
	do
		python3 download-ecmwf.py "`echo ${DATASETS[@]}`" \
			${step} ${ECMWF_DIR}/${step}.grb2;
		transform_data ${ECMWF_DIR}/${step}.grb2;
	done	
}

#Derive RH from 2m dewpoint 
#and temperature
#This should really be extracted
#in common.sh
function derive_rh {
	#Deriving date again, 
	#for readability:
	t=`cdo -s showtimestamp -seltimestep,1 ${1}`
        date=`date -d ${t} +'%Y%m%d%H%M'`
	${GDAL_PATH}/gdal_calc.py --overwrite --format=GTiff --type Int16 \
		${GDAL_CALC_OPTIONS} \
		--co=BLOCKXSIZE=128 --co=BLOCKYSIZE=128 \
		--calc='(exp(1.81+(A*17.27- 4717.31) / (A - 35.86))/exp(1.81+(B*17.27- 4717.31) / (B - 35.86)))*100' \
		--outfile=${ECMWF_DIR}/2r/tif/${date}.tif \
		-A ${1} --A_band=5 -B ${1} --B_band=4
}

#Derive wdir from 10u and 1v
function derive_wdir {
        t=`cdo -s showtimestamp -seltimestep,1 ${1}`
        date=`date -d ${t} +'%Y%m%d%H%M'`
	${GDAL_PATH}/gdal_calc.py --overwrite --format=GTiff \
           -A ${1} --A_band=2 \
           -B ${1} --B_band=3 \
           --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
           --calc='where(57.3*arctan2(-1*A,-1*B)<0,360+(57.3*arctan2(-1*A,-1*B)),57.3*arctan2(-1*A,-1*B))' \
           --outfile=${ECMWF_DIR}/wdir/tif/${date}.tif
}

#Derive wspd from 10u and 1v
function derive_wspd {
	t=`cdo -s showtimestamp -seltimestep,1 ${1}`
        date=`date -d ${t} +'%Y%m%d%H%M'`
	${GDAL_PATH}/gdal_calc.py --overwrite --format=GTiff -A ${1} -B ${1} \
      		--A_band=2 --B_band=3 \
      		--type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      		--calc='sqrt(A*A+B*B)' \
      		--outfile=${ECMWF_DIR}/wspd/tif/${date}.tif
}

#A function to eiher simply 
#convert a band to a Geotiff
#or derive from other band(s)
function transform_data {
	t=`cdo -s showtimestamp -seltimestep,1 ${1}`
	date=`date -d ${t} +'%Y%m%d%H%M'`
	counter=0
	for c in ${COVERAGESTORES[@]}
	do
		if [ ${DERIVED[$counter]} = 0 ]; then
			#simply transform the band:
			${GDAL_PATH}/gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} \
				-b ${BANDS[${counter}]} ${1} \
				${ECMWF_DIR}/${c}/tif/${date}.tif;
		elif [ ${DERIVED[$counter]} = 1 ]; then
			#Call the derive function defined 
			#in the FUNCTION array:
			${FUNCTION[${counter}]} ${1}
		fi
		(( counter++ ))
	done



}

function update_geoserver {
#Files are downloaded 
#and new GTiff granules derived 
#Now update mosaics:
   for c in ${COVERAGESTORES[@]}
   do 
      FILE_DIR=${ECMWF_DIR}/${c}
      #3.Re-index mosaic:
      find ${FILE_DIR}/tif -name '*.tif' \
	   -exec curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" \
	   -d "file://"{}  "${REST_URL}/${WORKSPACE}/coveragestores/${c}/external.imagemosaic" \;
      remove_files_from_mosaic ${c}
   done
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for cv in ${COVERAGES[@]}
	do
	   #delete granules from previous forecast
	   #(but retain first 24 hours)
	   #and granules older than 6 weeks:
	   #FORECAST_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo $FORECAST\``
	   SIX_WEEKS_AGO=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo ${FORECAST}\`-'6 weeks'`
	   filter="(time%20LT%20'${SIX_WEEKS_AGO}')"
	   TO_REMOVE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET \
		   "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=${filter}" \
		   |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
	   for g in ${TO_REMOVE[@]}
	   do
	   	curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
			"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=location='${g}'"
		rm -f ${g}
	   done
	   unset g
	done
}

download_data
#This is not enough 
#to deter the NetCDF plugin to 
#falsely detect Geotifs as NetCDF files:
find ${ECMWF_DIR} -name '*.tif' -exec ${GDAL_PATH}/gdal_edit.py -a_srs EPSG:4326 {} \; 
FORECAST=`cdo -s showtimestamp -seltimestep,1 ${ECMWF_DIR}/0.grb2 \
	|date --date='TZ="UTC"' +'%Y-%m-%dT%H:%M:%SZ'`
update_geoserver
#Clean up:
rm -f ${ECMWF_DIR}/*.grb2
find ${ECMWF_DIR} -name '*.aux.xml' -delete
exit 0
