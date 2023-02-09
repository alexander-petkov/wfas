#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

WORKSPACE="rtma"
RTMA_DIR=${DATA_DIR}/rtma
RTMA_FTP='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod'
REMOTE_FILES=() #initially empty array
DATASETS=('varanl' 'pcp')
PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp' 'rtma2p5.*.pcp.184.grb2' 'rtma2p5.*.2dvaranl_ndfd.grb2_wexp')
VARS=('2t' 'tcc' 'tp' '10si' '10wdir' '2r' 'solar')
DERIVED=(0 0 0 0 0 1 1)
FUNCTION=('' '' '' '' '' 'derive_rhm' 'compute_solar')
EXTRACT_FROM=('varanl' 'varanl' 'pcp' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 13 1 9 8 0 0)
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'
counter=0

ELEV_FILE=${RTMA_DIR}/rtma_dem.tif

function derive_rhm {
   gdal_calc.py --quiet --format=GTiff --type Int16 \
      --co=PROFILE=GeoTIFF --co=COMPRESS=DEFLATE --co=TILED=YES\
      --co=BLOCKXSIZE=128 --co=BLOCKYSIZE=128 \
      --co=NUM_THREADS=ALL_CPUS \
      --calc='(exp(1.81+(A*17.27- 4717.31) / (A - 35.86))/exp(1.81+(B*17.27- 4717.31) / (B - 35.86)))*100' \
      --outfile=${2} \
      -A ${1} --A_band=4 -B ${1} --B_band=3

   gdal_edit.py -a_srs "${PROJ4_SRS}" ${2}
}		      

function compute_solar {
   f=`echo ${1}|cut -d '/' -f 9-` #get last two tokens, containing dir and file name
   cloud_file=${RTMA_DIR}/varanl/tif/tcc/${f}
   minute=0
   hour=${cloud_file:68:2}
   day=${cloud_file:56:2}
   month=${cloud_file:54:2}
   year=${cloud_file:50:4}
   solar_grid --cloud-file ${cloud_file} \
           --num-threads 6 --day ${day} --month ${month} \
           --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
           ${ELEV_FILE} ${2}.asc
   gdal_translate -q -ot Int16 -of GTiff ${GEOTIFF_OPTIONS} ${2}.asc ${2}
   rm ${2}.{asc,prj}
}

function remove_file_from_mosaic {
   #Get a list of coverages for this mosaic:
   COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/rtma_${1}/coverages.xml \
               |grep -oP '(?<=<name>).*?(?=</name>)'`)
   for c in ${COVERAGES[@]}
   do
      #delete the granule:
      curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/rtma_${1}/coverages/${c}/index/granules.xml?filter=location='${2}'"
   done
}

function download_varanl {
   for file in ${REMOTE_FILES[@]}
   do
      indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT 1 from rtma.varanl_granules where granule='${file}'"`;
      if [ "${indexed}" != "1" ]; then 
      	ogrinfo -q PG:"host=${PG_HOST} user=docker password=docker dbname=wfas port=${PG_PORT}" \
		-sql "INSERT into rtma.varanl_granules values('${file}')"
      	wget -q --cut-dirs 6 -xnH -c --recursive --directory-prefix=${1} -N  --no-parent \
         -A${PATTERNS[counter]} \
         ${RTMA_FTP}/${file}
      fi
   done
   #printf "${RTMA_FTP}"/'%s\n' "${REMOTE_FILES[@]}" \
   #	   | xargs -P10  wget -q --cut-dirs 6 -c -i --directory-prefix=${1}  
}

function download_pcp {
   #Rewrite downloaded varanl file names to pcp file names, and download only those.
   #This is to ensure that varanl and pcp archives are with aligned timesteps.
   PCP_FILES=(`printf '%s\n' "${REMOTE_FILES[@]}"| \
	   awk '{print substr($0,1,17) substr($0,1,8) substr($0,9,8) substr($0,27,2) ".pcp.184.grb2"}'|sort`)
   
   #printf "${RTMA_FTP}"/'%s\n' "${PCP_FILES[@]}" \
   #	   | xargs -P10  wget -q --cut-dirs 6 -xnH -c -i --directory-prefix=${1} -N 
   for file in ${PCP_FILES[@]}
   do
	
      indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT 1 from rtma.pcp_granules where granule='${file}'"`;
      if [ "${indexed}" != "1" ]; then 
      	ogrinfo -q PG:"host=${PG_HOST} user=docker password=docker dbname=wfas port=${PG_PORT}" \
		-sql "INSERT into rtma.pcp_granules values('${file}')"
      	wget -q --cut-dirs 6 -xnH -c --directory-prefix=${1} -N  --no-parent \
   	   ${RTMA_FTP}/${file}
      fi
   done
}

#Build a list of files on the ftp server:
for d in `curl -s --list-only ${RTMA_FTP}/|grep 'rtma2p5\.'|sort` #a list of directories from ftp
do 
	for f in `curl -s --list-only ${RTMA_FTP}/${d}/ | grep 'varanl_ndfd.grb2_wexp$'|sort` #list varanl files in each directory
	do 
		REMOTE_FILES+=(`echo ${d}/${f}`) #add element to array
	done
done

#loop over RTMA datasets:
for d in ${DATASETS[@]}
do 
   #RTMA grib files local storage locations:
   FILE_DIR=${RTMA_DIR}/${d}

   #Sync to the most current RTMA FTP archive
   #Unless we have the Rel Humidity (rhm) dataset, 
   #which is derived from varanl data:
   if [ ! ${d} = 'rhm' ] ; then
      download_${d} $FILE_DIR/grb
   fi
   
   (( counter++ ))
done

counter=0

for var in ${VARS[@]}
do 
   FILE_DIR=${RTMA_DIR}/${EXTRACT_FROM[${counter}]}
   dataset=${EXTRACT_FROM[${counter}]}
   #Sorted list of locally stored Grib files:
   CUR_FILES=(`find ${FILE_DIR}/grb -type f |sort`)
   if [ ${var} = 'tp' ]; then
	   dtype='Float32'
   else
	   dtype='Int16'
   fi
   for i in ${CUR_FILES[@]}
   do
      f=`echo ${i}|cut -d '/' -f 9-` #get last two tokens, containing dir and file name

      if [ ! -f ${FILE_DIR}/tif/${var}/${f} ]; then
        dirname=`echo ${i}|cut -d '/' -f 9`
        mkdir -p ${FILE_DIR}/tif/${var}/${dirname}
	if [ ${DERIVED[${counter}]} = 1 ]; then
		${FUNCTION[${counter}]} ${i} ${FILE_DIR}/tif/${var}/${f}
	else
		gdal_translate -q -of GTiff -ot ${dtype} ${GEOTIFF_OPTIONS} -a_srs "${PROJ4_SRS}" \
			-b ${BAND[${counter}]} ${i} ${FILE_DIR}/tif/${var}/${f}
	fi
	find ${FILE_DIR}/tif/${var} -name '*.aux.xml' -delete
	#add new file to mosaic:
	curl -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XPOST \
		-H "Content-type: text/plain" -d "file://"${FILE_DIR}/tif/${var}/${f} \
	       	"${REST_URL}/${WORKSPACE}/coveragestores/rtma_${var}/external.imagemosaic"
      fi
   done
   
   #Get a list of coverages for this mosaic:
   COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/rtma_${var}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)
   #Sorted list of Mosaic granules:
   MOSAIC_FILES=`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/rtma_${var}/coverages/${COVERAGES[0]}/index/granules.xml |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`

   for i in ${MOSAIC_FILES[@]}
   do
      f=`echo ${i}|cut -d '/' -f 10-` #get last two tokens, containing dir and file name
      indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT 1 from rtma.${dataset}_granules where granule='${f}'"`;
      if [ "${indexed}" != "1" ]; then 
      #if [ ! -f ${FILE_DIR}/grb/${f} ]; then
	#remove from mosaic
	remove_file_from_mosaic $var $i
	#remove from file system
	#rm -f ${i}
      fi
   done
   #remove residual tif granules, if any:
   for f in `find ${FILE_DIR}/tif/${var} -path '*rtma*_wexp' -type f|rev|cut -d '/' -f 1,2|rev`
   do 
      indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT 1 from rtma.varanl_granules where granule='${f}'"`;
      if [ "${indexed}" != "1" ]; then 
	   #if [ ! -f  ${FILE_DIR}/grb/$f ] ; then 
	   rm ${FILE_DIR}/tif/${var}/${f} 
      fi 
   done
   #Remove empty directories:
   find ${FILE_DIR}/tif/${var} -empty -type d -name 'rtma2p5.*' -delete
   (( counter++ ))
done

for d in ${DATASETS[@]}
do 
   #RTMA grib files local storage locations:
   FILE_DIR=${RTMA_DIR}/${d}
   #Remove GRIB files:
   find ${FILE_DIR}/grb -type f -name '*grb*' -delete
   #Remove empty directories:
   find ${FILE_DIR}/grb -empty -type d -name 'rtma2p5.*' -delete
done

#export the last complete 24-hour periodstarting from 00:00 as a NetCDF package:
starttime=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT to_char(time-interval '29 hours','YYYY-MM-DD HH24:MI:SSZ') from rtma.\"Temperature\" order by time desc limit 1;"|sed -e 's/ /T/'`
#/mnt/cephfs/wfas/bin/netcdf_package_export.sh archive=${WORKSPACE} starttime="${starttime}"
