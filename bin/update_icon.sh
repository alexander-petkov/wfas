#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="icon"
DATASETS=('t_2m' 'relhum_2m' 'clct' 'aswdir_s' 'u_10m' 'v_10m' 'tot_prec') 
COVERAGESTORES=('t_2m' 'relhum_2m' 'clct' 'aswdir_s' 'wdir' 'wspd' 'tot_prec') 
DERIVED=(0 0 0 0 1 1 1) #is the coverage downloaded, or derived from other datasets?
FUNCTION=('' '' '' '' 'derive_wdir' 'derive_wspd' 'derive_precip') 


#ICON setup:
ICON_URL="https://opendata.dwd.de/weather/nwp/icon/grib/00"
ICON_DIR="${DATA_DIR}/icon"
TARGET_GRID_DESCRIPTION=${ICON_DIR}/ICON_GLOBAL2WORLD_0125_EASY/target_grid_world_0125.txt
WEIGHTS_FILE=${ICON_DIR}/ICON_GLOBAL2WORLD_0125_EASY/weights_icogl2world_0125.nc
#END ICON Setup

function derive_precip {
   FILE_DIR=${ICON_DIR}/${1}	
   for h in `seq 0 78 && seq 81 3 180`
   do
      current=$(printf "%03d" ${h})
      pcp_file=`find ${FILE_DIR} -name '*_'${current}'_TOT_PREC.grib2.0125'`
      t=`cdo -s showtimestamp -seltimestep,1 ${pcp_file}`
      date=`date -d ${t} +'%Y%m%d%H%M'`
      
      if (( $h==0 )); then
         gdal_translate -q -of GTiff -ot Float32 ${GEOTIFF_OPTIONS} \
           -a_srs wgs84 -b 1 ${pcp_file} \
           ${FILE_DIR}/${date}.tif
      elif (( $h>0 && $h<=78 )); then
	  previous=$(printf "%03d" $(( h - 1 )) )
	  prev_pcp_file=`find ${FILE_DIR} -name '*_'${previous}'_TOT_PREC.grib2.0125'`
	  gdal_calc.py --quiet -A ${1} --format=GTiff --type=Float32 ${GDAL_CALC_OPTIONS} \
		  -A ${pcp_file} \
		  -B ${prev_pcp_file} \
		  --calc='(A-B)' \
		  --outfile=${FILE_DIR}/${date}.tif
      elif (( $h>=81 && $h<=180 )); then
	  previous=$(printf "%03d" $(( h - 3 )) )
	  gdal_calc.py --quiet -A ${1} --format=GTiff --type=Float32 ${GDAL_CALC_OPTIONS} \
		  -A ${pcp_file} \
		  -B ${prev_pcp_file} \
		  --calc='(A-B)' \
		  --outfile=${FILE_DIR}/${date}.tif
      fi
      sleep 1
   done
}

function derive_wdir {
   FILE_DIR=${ICON_DIR}/$1
   for h in `seq -w 000 1 78 && seq -w 81 3 180`
   do
      u_file=`find ${ICON_DIR}/u_10m -name '*_'${h}'_U_10M*.0125'`
      v_file=`find ${ICON_DIR}/v_10m -name '*_'${h}'_V_10M*.0125'`
      if [ -s "${u_file}" -a -s "${v_file}" ] ; then
         w_file="${h}_WDIR_10M.grib2"
         cdo -s -O expr,'10wdir=((10u<0)) ? 360+10u:10u;' -mulc,57.3 -atan2 -mulc,-1 \
	   ${u_file} -mulc,-1 \
	   ${v_file} \
	   ${FILE_DIR}/${w_file}
         t=`cdo -s showtimestamp -seltimestep,1 ${FILE_DIR}/${w_file}`
         date=`date  -d $t +'%Y%m%d%H%M'` 
         gdal_translate -q -of GTiff -ot Int16 ${GEOTIFF_OPTIONS}  -a_srs wgs84 -b 1 \
	   ${FILE_DIR}/${w_file} \
	   ${FILE_DIR}/${date}.tif
	 rm ${FILE_DIR}/${w_file}  
      fi
   done
}
function derive_wspd {
   FILE_DIR=${ICON_DIR}/$1
   for h in `seq -w 000 1 78 && seq -w 81 3 180`
   do
      u_file=`find ${ICON_DIR}/u_10m -name '*_'${h}'_U_10M*.0125'`
      v_file=`find ${ICON_DIR}/v_10m -name '*_'${h}'_V_10M*.0125'`
      if [ -s "${u_file}" -a -s "${v_file}" ] 
      then
         wspd_file="${h}_WSPD_10M.grib2"
         cdo -s -O -expr,'10si=(sqrt(10u*10u+10v*10v))' -merge \
	   ${u_file} ${v_file} ${FILE_DIR}/${wspd_file}
         t=`cdo -s showtimestamp -seltimestep,1 ${FILE_DIR}/${wspd_file}`
         date=`date  -d $t +'%Y%m%d%H%M'` 
         gdal_translate -q -of GTiff -ot Float32 ${GEOTIFF_OPTIONS} -a_srs wgs84 \
	   ${FILE_DIR}/${wspd_file} \
	   ${FILE_DIR}/${date}.tif
      fi
   done
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

function download_data {
   #Download ICON datasets
   for d in ${DATASETS[@]}
   do 
      #ICON files local storage locations:
      FILE_DIR=${ICON_DIR}/${d}/
      echo ${FILE_DIR}
      #Sync to the most current ICON forecast run at 00
      wget  -qbcr -np -nd -A .bz2 --cut-dirs=5 \
	      "${ICON_URL}/${d}/" -P ${FILE_DIR}
   done
   #check download status:
   #while [ `find ${ICON_DIR} -name '*_180_*.bz2'|wc -l` != ${#DATASETS[@]} ]
   while [ `ps -efw|grep wget|grep opendata|wc -l` != '0' ]
   do
	sleep 3m
   done

}

function isohedral2latlon { 
   for d in ${DATASETS[@]}
   do
      #ICON files local storage locations:
      FILE_DIR=${ICON_DIR}/${d}
      find ${FILE_DIR} -name '*.bz2' -exec bunzip2 {} \;
      find ${FILE_DIR} -name '*.grib2' \
	      -exec cdo -s -f grb2 \
	      remap,${TARGET_GRID_DESCRIPTION},${WEIGHTS_FILE} {} {}.0125 \;
      find ${FILE_DIR} -name '*.grib2' -type f -delete
   done
}

function make_geotiffs {
   counter=0
   for c in ${COVERAGESTORES[@]}
   do
      if [ ${DERIVED[${counter}]} = 0 ] ; then
	 FILE_DIR=${ICON_DIR}/${c}
         for file in `find ${FILE_DIR} -name '*.0125'`
	 do
	      t=`cdo -s showtimestamp -seltimestep,1 ${file}`
              date=`date -d ${t} +'%Y%m%d%H%M'`
	      gdal_translate -q -ot Int16 -of GTiff ${GEOTIFF_OPTIONS} \
		      -a_srs wgs84 ${file} ${FILE_DIR}/${date}.tif
	 done
      else
	      ${FUNCTION[${counter}]} ${c}
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
      #1. Clear old granules from Geoserver's catalog and file system:
      #ICON files local storage locations:
      FILE_DIR=${ICON_DIR}/${c}
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
download_data
isohedral2latlon
#Get forecast start date in YYYYMMDD format
#by scraping the first filename for temperature:
FORECAST=`find ${ICON_DIR}/t_2m -name '*.0125'|head -n 1|rev \
	|cut -d '_' -f 4 |rev|cut -c 1-8` 
echo ${FORECAST}
make_geotiffs
update_geoserver
#remove old granules from system:
find ${ICON_DIR} -name '*.grib2*' -type f -delete ;
