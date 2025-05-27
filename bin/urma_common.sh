#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

counter=0

function derive_rhm {
   ${GDAL_PATH}/gdal_calc.py  --format=GTiff --type Int16 ${GDAL_CALC_OPTIONS} \
      --co=BLOCKXSIZE=128 --co=BLOCKYSIZE=128 \
      --calc='(exp(1.81+(A*17.27- 4717.31) / (A - 35.86))/exp(1.81+(B*17.27- 4717.31) / (B - 35.86)))*100' \
      --outfile=${2} \
      -A ${1} --A_band=4 -B ${1} --B_band=3
   ${GDAL_PATH}/gdal_edit.py -a_srs "${PROJ4_SRS}" ${2}
}		      

function compute_solar {
   ${GDAL_PATH}/gdal_translate -q -of GTiff \
	   -ot ${dtype} ${GEOTIFF_OPTIONS} \
	   -a_srs "${PROJ4_SRS}" \
           -b ${BAND[${counter}]} ${1} ${2}.cloud
   f=`echo ${2}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
   fdate=`echo ${f}| sed 's/.*\([[:digit:]]\{8\}\)\+.*t\([[:digit:]]\{2\}\)z.*/\1 \2/'`
   minute=0
   hour=${fdate:8:2}
   day=${fdate:6:2}
   month=${fdate:4:2}
   year=${fdate:0:4}
   solar_grid --cloud-file ${2}.cloud \
           --num-threads 6 --day ${day} --month ${month} \
           --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
           ${ELEV_FILE} ${2}.asc
   ${GDAL_PATH}/gdal_translate -q -ot Int16 -of GTiff ${GEOTIFF_OPTIONS} ${2}.asc ${2}
   rm -f ${2}.{asc,xml,prj,cloud}
}

function get_remote_files {
#Build a list of files on the ftp server:
for d in `curl -s --list-only ${FTP_DIR}/|grep "^${FTP_DIR_PATTERN}"|sort` #a list of directories from ftp
do
	for f in `curl -s --list-only ${FTP_DIR}/${d}/ | grep "${FTP_FILE_PATTERN}$"|sort` #list varanl files in each directory
	do 
		REMOTE_FILES+=(`echo ${d}/${f}`) #add element to array
	done
done
}

function download_data {
   for file in ${REMOTE_FILES[@]}
   do
	   indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT count(granule) from ${WORKSPACE}.granule_idx where granule='${file}'"`;
      if [ "${indexed}" = "0" ]; then
      	${OGR_PATH}/ogrinfo -q PG:"host=${PG_HOST} user=docker password=docker dbname=wfas port=${PG_PORT}" \
		-sql "INSERT into ${WORKSPACE}.granule_idx values('${file}')"
      	wget -q --cut-dirs 6 -xnH -c --recursive \
		--directory-prefix=${URMA_DIR}/granules \
		-N  --no-parent \
		${FTP_DIR}/${file}
	 pcp_file=`printf ${file}| \
           awk '{print substr($0,1,17) substr($0,1,8) substr($0,9,8) substr($0,27,2) ".pcp_01h.wexp.grb2"}'`

      	wget -q --cut-dirs 6 -xnH -c --recursive \
		--directory-prefix=${URMA_DIR}/granules \
		-N  --no-parent \
		${FTP_DIR}/${pcp_file}
      fi
   done
}


function process_new_granules {

counter=0

for var in ${VARS[@]}
do 
   if [ ${var} = 'tp' ]; then
	   dtype='Float32'
	   replace_pattern="pcp_01h.wexp.grb2"
   else
	   dtype='Int16'
	   replace_pattern="2dvaranl_ndfd.grb2_wexp"
   fi
   #Sorted list of locally stored Grib files:
   CUR_FILES=(`find ${URMA_DIR}/granules -name '*'${replace_pattern}'*' |sort`)
   for i in ${CUR_FILES[@]}
   do
      f=`echo ${i}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
      f=${f/$replace_pattern/tif} #replace any mention of grb with tif extension
      if [ ! -f ${FILE_DIR}/${var}/${f} ]; then
        dirname=`echo ${i}|rev|cut -d '/' -f 2|rev`
        mkdir -p ${URMA_DIR}/${var}/${dirname}
	if [ ${DERIVED[${counter}]} = 1 ]; then
		${FUNCTION[${counter}]} ${i} ${URMA_DIR}/${var}/${f}
	else
		${GDAL_PATH}/gdal_translate -q -of GTiff -ot ${dtype} ${GEOTIFF_OPTIONS} -a_srs "${PROJ4_SRS}" \
			-b ${BAND[${counter}]} ${i} ${URMA_DIR}/${var}/${f}
	fi
	#Replace the word GRIB in binary files
	#This is to ensure that the NetCDF plugin
	#doesn't pick up the mosaic as GRIB files:
	find ${URMA_DIR}/${var} -name '*.tif' \
		-exec sed -i -e 's/GRIB/GDAL/' {} \;
      fi
   done
   #Reindex the mosaic:
   find ${URMA_DIR}/${var} -name '*.tif' \
	   -exec curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} \
	   -XPOST -H "Content-type: text/plain" -d "file://"{} \
	   "${REST_URL}/${WORKSPACE}/coveragestores/${var}/external.imagemosaic" \;
   #Get rid of auto generated stat files:
   find ${URMA_DIR}/${var} -name '*.aux.xml' -delete
   (( counter++ ))
done
}

function remove_old_granules {

counter=0

for var in ${VARS[@]}
do 
   dataset=${EXTRACT_FROM[${counter}]}
   RETENTION_PERIOD_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`date +%Y-%m-%dT%H:%M:%SZ\`-"${RETENTION_PERIOD}"`
   filter="(time%20LT%20'${RETENTION_PERIOD_START}')"
   #Get a list of coverages for this mosaic, 
   #should be array with a single element:
   COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${var}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)
   c="${COVERAGES[0]}"
   #Sorted list of Mosaic granules:
   TO_DELETE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${var}/coverages/${c}/index/granules.xml?filter=${filter}" |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
   for i in ${TO_DELETE[@]}
   do
      #get last two tokens, containing dir and file name:
      f=`echo ${i}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
      #delete the granule from mosaic:
      curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${var}/coverages/${c}/index/granules.xml?filter=location='${i}'"
      psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "DELETE from ${WORKSPACE}.granule_idx where granule='${f}'";
      #remove from file system
      rm -f ${i}
   done
   (( counter++ ))
done
}

function clean_up {
   #1. Remove GRIB files:
   find ${URMA_DIR}/granules -type f -name '*grb*' -delete
   #2. Remove empty directories:
   find ${URMA_DIR} -empty -type d -name "${FTP_DIR_PATTERN}*" -delete
   #3. Update to latest granule index:
   #Convert bash array to Postgresql array:
   printf -v psql_array "'%s'::varchar," "${REMOTE_FILES[@]//\'/\'\'}"
   #Remove delimiter after last element:
   psql_array=${psql_array%,}
   #Update the index:
   psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "DELETE from urma.granule_idx where granule not in (select unnest (ARRAY[$psql_array]) as a1)"

}

