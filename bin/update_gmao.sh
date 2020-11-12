#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="gmao"
GMAO_DIR=${DATA_DIR}/gmao
REMOTE_SRV='https://opendap.nccs.nasa.gov/dods/GEOS-5/fp/0.25_deg/fcast'
LAT_EXT='[448:572]'
LON_EXT='[128:383]'
TIME_EXT='[0:239]' #until I figure out how to specify a whole dimension w/o indexes
DATASETS=('tavg1_2d_slv_Nx'  'inst1_2d_lfo_Nx'  'tavg1_2d_flx_Nx'  'tavg1_2d_rad_Nx' )

FILTERS=('t2m'${TIME_EXT}${LAT_EXT}${LON_EXT}',v10m'${TIME_EXT}${LAT_EXT}${LON_EXT}',u10m'${TIME_EXT}${LAT_EXT}${LON_EXT}',time'${TIME_EXT}',lat'${LAT_EXT}',lon'${LON_EXT} \
	'tlml'${TIME_EXT}${LAT_EXT}${LON_EXT}',ps'${TIME_EXT}${LAT_EXT}${LON_EXT}',qlml'${TIME_EXT}${LAT_EXT}${LON_EXT}',time'${TIME_EXT}',lat'${LAT_EXT}',lon'${LON_EXT} \
	'prectot'${TIME_EXT}${LAT_EXT}${LON_EXT}',time'${TIME_EXT}',lat'${LAT_EXT}',lon'${LON_EXT} \
	'swgdn'${TIME_EXT}${LAT_EXT}${LON_EXT}',cldtot'${TIME_EXT}${LAT_EXT}${LON_EXT}',time'${TIME_EXT}',lat'${LAT_EXT}',lon'${LON_EXT} \
)

VARS=('t2m' 'wdir' 'wspd' 'rh' 'prectot' 'cldtot' 'swgdn')
times=()
TIME_REGEX='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}' #match YYYY-MM-DDTHH pattern
counter=0 

function get_times {
	times=(`ncdump -i -v time ${1} \
		|grep -o -E "${TIME_REGEX}" \
		|tr -d '[\-T]' \
		|tail -n +2` )
}

function derive_rh {
   NCFILE=${GMAO_DIR}/${DATASETS[1]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":tlml|grep '^Band'| wc -l`
   get_times ${NCFILE}
   for b in `seq  1 ${NUM_BANDS}`
   do
      OUTFILE=${GMAO_DIR}/rh/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_calc.py --quiet --format=GTiff --type=Int16 \
	 --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
         -A NETCDF:"${NCFILE}":tlml --A_band=${b} \
         -B NETCDF:"${NCFILE}":ps   --B_band=${b} \
	 -C NETCDF:"${NCFILE}":qlml --C_band=${b} \
         --calc='( C * B / (0.378 * C + 0.622))/(6.112 * exp((17.67 * (A-273.15))/(A-29.65)))' \
	 --outfile=${OUTFILE}
      gdal_edit.py -a_srs EPSG:4326 ${OUTFILE}
   done
 }

function derive_swgdn {
   NCFILE=${GMAO_DIR}/${DATASETS[3]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":swgdn|grep '^Band'| wc -l`
   get_times ${NCFILE}

   for b in `seq  1 ${NUM_BANDS}`
   do
      OUTFILE=${GMAO_DIR}/swgdn/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_translate -q -of GTiff -a_srs EPSG:4326 ${GEOTIFF_OPTIONS} -b ${b} \
         NETCDF:"${NCFILE}":swgdn ${OUTFILE}
   done
}

function derive_cldtot {
   NCFILE=${GMAO_DIR}/${DATASETS[3]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":cldtot|grep '^Band'| wc -l`
   get_times ${NCFILE}

   for b in `seq  1 ${NUM_BANDS}`
   do
      OUTFILE=${GMAO_DIR}/cldtot/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -b ${b} \
         NETCDF:"${NCFILE}":cldtot ${OUTFILE}
   done
}

function derive_prectot {
   NCFILE=${GMAO_DIR}/${DATASETS[2]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":prectot|grep '^Band'| wc -l`
   get_times ${NCFILE}

   for b in `seq  1 ${NUM_BANDS}`
   do
      OUTFILE=${GMAO_DIR}/prectot/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_calc.py --quiet --format=GTiff --type=Float32 \
              --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
	 -A NETCDF:"${NCFILE}":prectot --A_band=${b} \
	 --calc='A*3600' \
	 --outfile=${OUTFILE}
   done
}

function derive_t2m {
   NCFILE="${GMAO_DIR}/${DATASETS[0]}.nc4"
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":t2m|grep '^Band'| wc -l`
   get_times ${NCFILE}
   
   for b in `seq  1 ${NUM_BANDS}`
   do
      gdal_translate -q -of GTiff -a_srs EPSG:4326 ${GEOTIFF_OPTIONS} -b ${b} \
	      NETCDF:"${NCFILE}":t2m ${GMAO_DIR}/t2m/${times[$(( b-1 ))]}.tif
   done
}

function derive_wdir {
	      # expression from https://gis.stackexchange.com/questions/327957/what-is-the-correct-gdal-calc-syntax
      	      # this shows Wind Direction TO (we need Wind Direction From ):
	      #((degrees (arctan2 (A,B)))+360)*((degrees (arctan2 (A,B)))<0)+(degrees (arctan2 (A,B)))*((degrees (arctan2 (A,B)))>=0)
   NCFILE=${GMAO_DIR}/${DATASETS[0]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":u10m|grep '^Band'| wc -l`
   get_times ${NCFILE}
   
   for b in `seq  1 ${NUM_BANDS}`
   do 
      OUTFILE=${GMAO_DIR}/wdir/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_calc.py --quiet --format=GTiff --type=Float32 \
              --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
	      -A NETCDF:"${NCFILE}":u10m --A_band=${b} \
	      -B NETCDF:"${NCFILE}":v10m --B_band=${b} \
	      --calc='(((arctan2 ((-1*A),(-1*B)))*57.3)+360)*(((arctan2 ((-1*A),(-1*B)))*57.3)<0)+((arctan2 ((-1*A),(-1*B)))*57.3)*(((arctan2 ((-1*A),(-1*B)))*57.3)>=0)' \
	      --outfile ${OUTFILE} 
      gdal_edit.py -a_srs EPSG:4326 ${OUTFILE}
   done
}

function derive_wspd {
   NCFILE=${GMAO_DIR}/${DATASETS[0]}.nc4
   NUM_BANDS=`gdalinfo NETCDF:"${NCFILE}":u10m|grep '^Band'| wc -l`
   get_times ${NCFILE}

   for b in `seq  1 ${NUM_BANDS}`
   do 
      OUTFILE=${GMAO_DIR}/wspd/${times[$((b-1))]}.tif #subtract b/c arrays are 0-based
      gdal_calc.py --quiet --format=GTiff --type=Float32 \
	      --NoDataValue=-9999 ${GDAL_CALC_OPTIONS} \
	      -A NETCDF:"${NCFILE}":u10m --A_band=${b} \
	      -B NETCDF:"${NCFILE}":v10m --B_band=${b} \
	      --calc='sqrt(A*A+B*B)' \
	      --outfile ${OUTFILE} 
      gdal_edit.py -a_srs EPSG:4326 ${OUTFILE}
   done
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   echo ${c}
	   curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml"
	done
}

#Download GEOS datasets
for d in ${DATASETS[@]}
do 
   #Get latest forecast for this dataset:
   FORECAST=`curl -s -l "${REMOTE_SRV}/${d}" \
	   |cut -d '"' -f 2|grep '_00:'|cut -d ':' -f 1| tail -n 1`
   echo ${FILTERS[${counter}]}
   nccopy "${REMOTE_SRV}/${d}/${FORECAST}?${FILTERS[${counter}]}" ${GMAO_DIR}/${d}.nc4
   (( counter++ ))
done

counter=0

#Extract Getiffs from Netcdf files:
for v in ${VARS[@]}
do
    derive_${v}
done
#Files are downloaded 
#and new GTiff granules derived 
#in previous loop.
#Now update mosaics:
for v in ${VARS[@]}
do 
#1. Clear old granules from Geoserver's catalog and file system:
   #GМАО files local storage locations:
   FILE_DIR=${GMAO_DIR}/${v}
   #remove granules from mosaic catalog:
   remove_files_from_mosaic ${v}
   #remove old granules from system:
   rm  ${FILE_DIR}/tif/*.tif*
   find ${FILE_DIR} -empty -type f -delete ;
#2. Move new granules in place:
   mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
#3.Re-index mosaic:
   find ${FILE_DIR}/tif -name '*.tif' -type f -exec curl -s -u admin:geoserver -H "Content-type: text/plain" -d "file://"{}  "${REST_URL}/${WORKSPACE}/coveragestores/${v}/external.imagemosaic" \;
done
   
rm ${GMAO_DIR}/*.nc4 ;
