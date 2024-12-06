#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="rap"
COVERAGESTORES=('TMP' 'RH' 'APCP' 'TCDC' 'WDIR' 'WSPD' 'DSWRF') 
DATASETS=('wrfnat')

#String of bands for gdal_translate to extract:
# First element in the array is a list of bands for hours F00 and F01
# Second element in the array is a list of bands for hours F00-F21, and \
# up to F51 for the extended forecasts.

REMOTE_BANDS=( "-b 1030 -b 1032 -b 1034 -b 1035 -b 1037 -b 1064 -b 1072" \
	"-b 1030 -b 1032 -b 1034 -b 1035 -b 1037 -b 1068 -b 1076" \
      )
BAND=(1 0 5 6 3 4 7)
DERIVED=(0 1 1 0 1 1 0) #is the coverage downloaded, or derived from other datasets?
FUNCTION=('' 'derive_rh' 'derive_precip' '' 'derive_wdir' 'derive_wspd' '') 


#RAP setup:
RAP_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/rap/prod"
latest_forecast=`curl -s --list-only ${RAP_URL}/|grep -oP '(?<=">)rap\..*(?=/</a>)'|sort|tail -n1`
FORECAST=`echo ${latest_forecast} | cut -d '.' -f 2`
FORECAST_URL="https://noaarap.blob.core.windows.net/rap/${latest_forecast}"
RAP_DIR="${DATA_DIR}/rap"

#build a filter to delete granules from previous forecast
#(but retain first 24 hours)
#and granules older than 6 weeks:
#also, add 3 hours to start of forecast, 
#because dataset for F00 is valid for F03 and so on,
#and we collect from F01
FORECAST_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo ${FORECAST}\`+'4 hours'`
SIX_WEEKS_AGO=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo ${FORECAST}\`-'6 weeks'`
filter="(time%20LT%20'${SIX_WEEKS_AGO}'%20OR%20time%20GTE%20'${FORECAST_START}')"
#END RAP Setup

#FUNCTION: derive_wdir
#Derives wind direction from u and v components
#Called from: make_geotiffs
#Input Arguments:
#1. Input Grib file
#2. Output file name 
function derive_wdir {
   ${GDAL_PATH}/gdal_calc.py --format=GTiff -A ${1} -B ${1} \
      --A_band=3 --B_band=4 \
      --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      --calc='where(57.3*arctan2(-1*A,-1*B)<0,360+(57.3*arctan2(-1*A,-1*B)),57.3*arctan2(-1*A,-1*B))' \
      --outfile=${2}
}

#FUNCTION: derive_precip
#Calculates hourly precip 
#from APCP files, by subtracting previous hour, 
#unless hour is F01
#Called from: make_geotiffs
#Input Arguments:
#1. Input 7-band file
#2. Output file name
function derive_precip {
   h=`echo ${1}|rev|cut -c 5,6|rev`
   if [ $h -eq 1 ]; then
      ${GDAL_PATH}/gdal_translate -q -b 5 \
      -of GTiff -ot Float32 ${GEOTIFF_OPTIONS} \
      ${1} ${2}
   elif  [ $h -gt 1 ]; then
      prev=$(printf "%02d" $((10#${h}-1)) )
      ${GDAL_PATH}/gdal_calc.py --format=GTiff -A ${1} -B "${1/f${h}/f${prev}}" \
         --A_band=5 --B_band=5 \
         --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
         --calc='(A-B)' \
	 --outfile=${2}
   fi
}

#FUNCTION: derive_wspd
#Derives wind speed from u and v components
#Called from: make_geotiffs
#Input Arguments:
#1. Input Grib file
#2. Output file name 
function derive_wspd {
   gdal_calc.py --quiet --format=GTiff -A ${1} -B ${1} \
      --A_band=3 --B_band=4 \
      --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      --calc='sqrt(A*A+B*B)' \
      --outfile=${2}
}

#FUNCTION: derive_rh
#Derivesrelative humidity 
#from dewpoint and temperature at 2m.
#Called from: make_geotiffs
#Input Arguments:
#1. Input file with Dewpoint and Tempprature
#2. Output file name 
function derive_rh {
   gdal_calc.py --quiet --format=GTiff --type Int16 ${GDAL_CALC_OPTIONS} \
      --co=BLOCKXSIZE=128 --co=BLOCKYSIZE=128 \
      --calc='(exp(1.81+(A*17.27- 4717.31) / (A - 35.86))/exp(1.81+(B*17.27- 4717.31) / (B - 35.86)))*100' \
      --outfile=${2} \
      -A ${1} --A_band=2 -B ${1} --B_band=1
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for cv in ${COVERAGES[@]}
	do
	   TO_REMOVE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET \
		   "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=${filter}" \
		   |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
	   for g in ${TO_REMOVE[@]}
	   do
	   	curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
			"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=location='${g}'"
		rm -f ${g} ${g}.xml
	   done
	   unset g
	done
}

function process_data {
   #Download RAP datasets
   for h in `seq -w 01 51`
   do
      [ $h -lt 2  ] && BANDS=${REMOTE_BANDS[0]} || BANDS=${REMOTE_BANDS[1]}
      ${GDAL_PATH}/gdal_translate -q ${BANDS} -of GTiff \
         -a_srs "+proj=ob_tran +o_proj=eqc +o_lon_p=180 +o_lat_p=144 +lon_0=74 +R=6371229" \
	 -outsize 953 834 \
	 -a_ullr -6448701.88 -5642620.27 6448707.45 5642616.94 \
	 ${GEOTIFF_OPTIONS} \
	 /vsicurl/"${FORECAST_URL}/rap.t03z.wrfnatf${h}.grib2" \
	 ${RAP_DIR}/rap.t03z.wrfnatf${h}.tif
      make_geotiffs ${RAP_DIR}/rap.t03z.wrfnatf${h}.tif
   done

}

function make_geotiffs {
   counter=0
   for c in ${COVERAGESTORES[@]}
   do
      FILE_DIR=${RAP_DIR}/${c}
      EPOCHTIME=`${GDAL_PATH}/gdalinfo ${1} \
              |grep -i GRIB_VALID_TIME -m 1 \
              |cut -d '=' -f2`
      date=`date --date='@'${EPOCHTIME} +'%Y%m%d%H%M'`
      if [ ${DERIVED[${counter}]} = 0 ] ; then
	 ${GDAL_PATH}/gdalwarp -q -overwrite \
	   -ot Float32 -of GTiff \
	   -b ${BAND[${counter}]} ${GEOTIFF_OPTIONS} \
           -t_srs wgs84 \
	   -te -180.0000000 -10.6531627 0 90 \
	   ${1} ${FILE_DIR}/${date}.tif
      else
	#send input and output file names as arguments 1 and 2:
	${FUNCTION[${counter}]} ${1} ${FILE_DIR}/${date}.tif.tmp
	${GDAL_PATH}/gdalwarp -q -overwrite -t_srs WGS84 \
		-te -180.0000000 -10.6531627 0 90 \
		${GEOTIFF_OPTIONS} -overwrite \
		${FILE_DIR}/${date}.tif.tmp \
		${FILE_DIR}/${date}.tif
      fi
      rm -f ${FILE_DIR}/*.tif.tmp ${FILE_DIR}/*.aux.xml
      (( counter++ ))
   done
}

function update_geoserver {
#Files are downloaded 
#and new GTiff granules derived 
#Now update mosaics:
   for c in ${COVERAGESTORES[@]}
   do 
      #1. Clear old granules from Geoserver's catalog and file system:
      #RAP files local storage locations:
      FILE_DIR=${RAP_DIR}/${c}
      #remove granules from mosaic catalog:
      remove_files_from_mosaic ${c}
      #2. Move new granules in place:
      mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
      #3.Re-index mosaic:
      find ${FILE_DIR}/tif -name '*.tif' \
	   -exec curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -H "Content-type: text/plain" \
	   -d "file://"{}  "${REST_URL}/${WORKSPACE}/coveragestores/${c}/external.imagemosaic" \;
   done
}
process_data
update_geoserver
#remove old granules from system:
find ${RAP_DIR} -name 'rap.*.tif*' -type f -delete ;
