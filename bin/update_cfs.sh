#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="cfs"
COVERAGESTORES=('2t' '2r' 'tcc' 'dswrf' 'wdir' 'wspd' 'prate') 
DATASETS=('flx' 'pgb' 'flx' 'flx' 'flx' 'flx' 'flx') 
DATASETS=('flx')
BAND=(38 368 53 16 0 0 31)
DERIVED=(0 1 0 0 1 1 0) #is the coverage downloaded, or derived from other datasets?
FUNCTION=('' 'derive_rh' '' '' 'derive_wdir' 'derive_wspd' '') 


#CFS setup:
CFS_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/cfs/prod"
latest_forecast=`curl -s --list-only ${CFS_URL}/|grep -oP '(?<=">)cfs.*(?=/</a>)'|sort|tail -n1`
FORECAST=`echo ${latest_forecast} | cut -d '.' -f 2`
FORECAST_URL="${CFS_URL}/${latest_forecast}/00/6hrly_grib_01/"
CFS_DIR="${DATA_DIR}/cfs"
#END CFS Setup

#FUNCTION: derive_wdir
#Derives wind direction from u and v components
#Called from: make_geotiffs
#Input Arguments:
#1. Input Grib file
#2. Output file name 
function derive_wdir {
   gdal_calc.py --format=GTiff -A ${1} -B ${1} \
      --A_band=36 --B_band=37 \
      --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      --calc='where(57.3*arctan2(-1*A,-1*B)<0,360+(57.3*arctan2(-1*A,-1*B)),57.3*arctan2(-1*A,-1*B))' \
      --outfile=${2}
}

#FUNCTION: derive_wspd
#Derives wind speed from u and v components
#Called from: make_geotiffs
#Input Arguments:
#1. Input Grib file
#2. Output file name 
function derive_wspd {
   gdal_calc.py --format=GTiff -A ${1} -B ${1} \
      --A_band=36 --B_band=37 \
      --type=Float32 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      --calc='sqrt(A*A+B*B)' \
      --outfile=${2}
}

#FUNCTION: derive_rh
#Derivesrelative humidity 
#from specific humidity and pressure.
#Called from: make_geotiffs
#Input Arguments:
#1. Input Grib file
#2. Output file name 
function derive_rh {
   gdal_calc.py --format=GTiff --type=Int16 \
      --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      -A ${1} --A_band=38 \
      -B ${1} --B_band=40 \
      -C ${1} --C_band=39 \
      --calc='( C * B / (0.378 * C + 0.622))/(6.112 * exp((17.67 * (A-273.15))/(A-29.65)))' \
      --outfile=${FILE_DIR}/rh.tmp
   gdal_calc.py --format=GTiff --type=Int16 \
      --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
      -A ${FILE_DIR}/rh.tmp --A_band=1 \
      --calc="where(A>100,100,(where(A<0,0,A)))" \
      --outfile=${2}
   rm ${FILE_DIR}/rh.tmp
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for cv in ${COVERAGES[@]}
	do
	   #delete granules from previous forecast
	   #(but retain first 24 hours)
	   #and granules older than 6 weeks:
	   FORECAST_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo $FORECAST\``
	   SIX_WEEKS_AGO=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`echo $FORECAST\`-'6 weeks'`
	   filter="(time%20LT%20'${SIX_WEEKS_AGO}'%20OR%20time%20GTE%20'${FORECAST_START}')"
	   TO_REMOVE=(`curl -s -u admin:geoserver -XGET \
		   "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=${filter}" \
		   |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
	   for g in ${TO_REMOVE[@]}
	   do
	   	curl -s -u admin:geoserver -XDELETE \
			"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${cv}/index/granules.xml?filter=location='${g}'"
		rm -f ${g} ${g}.xml
	   done
	   unset g
	done
}

function process_data {
   #Download CFS datasets
   for d in `printf "%s\n" "${DATASETS[@]}" | sort -u`
   do 
      #get a list of files from remote server:
      REMOTE_FILES=`curl -s --list-only "${FORECAST_URL}" |grep  -oP '(?<=href=")'${d}'.*.grb2(?=")'|sort|head -n 56`
      #REMOTE_FILES=(`ls ${CFS_DIR}/*.grb2`)
      for r in ${REMOTE_FILES[@]}
      do
	      wget -q "${FORECAST_URL}/${r}" -O ${CFS_DIR}/${r}
	      make_geotiffs ${CFS_DIR}/${r}
      done
   done

}

function make_geotiffs {
   counter=0
   for c in ${COVERAGESTORES[@]}
   do
      FILE_DIR=${CFS_DIR}/${c}
      t=`cdo -s showtimestamp -seltimestep,1 ${1}`
      date=`date -d ${t} +'%Y%m%d%H%M'`
      if [ ${DERIVED[${counter}]} = 0 ] ; then
	 gdal_translate -q -ot Int16 -of GTiff \
	   -b ${BAND[${counter}]} ${GEOTIFF_OPTIONS} \
           -a_srs wgs84 ${1} ${FILE_DIR}/${date}.tif.tmp
      else
	#send input and output file names as arguments 1 and 2:
	${FUNCTION[${counter}]} ${1} ${FILE_DIR}/${date}.tif.tmp
      fi
      cp ${CFS_DIR}/template.vrt ${FILE_DIR}/${date}.vrt
      sed -i -e 's/to_replace/'${date}'.tif.tmp/' ${FILE_DIR}/${date}.vrt
      gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} \
	${FILE_DIR}/${date}.vrt ${FILE_DIR}/${date}.tif
      rm ${FILE_DIR}/${date}.vrt ${FILE_DIR}/${date}.tif.tmp ${FILE_DIR}/${date}.tif.aux.xml
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
      #CFS files local storage locations:
      FILE_DIR=${CFS_DIR}/${c}
      #remove granules from mosaic catalog:
      remove_files_from_mosaic ${c}
      #2. Move new granules in place:
      mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
      #3.Re-index mosaic:
      find ${FILE_DIR}/tif -name '*.tif' \
	   -exec curl -s -u admin:geoserver -H "Content-type: text/plain" \
	   -d "file://"{}  "${REST_URL}/${WORKSPACE}/coveragestores/${c}/external.imagemosaic" \;
   done
}
process_data
update_geoserver
#remove old granules from system:
find ${CFS_DIR} -name '*.grb2*' -type f -delete ;
