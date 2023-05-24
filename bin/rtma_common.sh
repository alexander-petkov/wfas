#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

counter=0

function derive_rhm {
   gdal_calc.py --format=GTiff --type Int16 ${GDAL_CALC_OPTIONS} \
      --co=BLOCKXSIZE=128 --co=BLOCKYSIZE=128 \
      --calc='(exp(1.81+(A*17.27- 4717.31) / (A - 35.86))/exp(1.81+(B*17.27- 4717.31) / (B - 35.86)))*100' \
      --outfile=${2} \
      -A ${1} --A_band=4 -B ${1} --B_band=3

   gdal_edit.py -a_srs "${PROJ4_SRS}" ${2}
}		      

function compute_solar {
   f=`echo ${1}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
   cloud_file=${RTMA_DIR}/varanl/tif/tcc/${f}
   fdate=`echo ${cloud_file}| sed 's/.*\([[:digit:]]\{8\}\)\+.*t\([[:digit:]]\{2\}\)z.*/\1 \2/'`
   minute=0
   hour=${fdate:8:2}
   day=${fdate:6:2}
   month=${fdate:4:2}
   year=${fdate:0:4}
   solar_grid --cloud-file ${cloud_file} \
           --num-threads 6 --day ${day} --month ${month} \
           --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
           ${ELEV_FILE} ${2}.asc
   gdal_translate -q -ot Int16 -of GTiff ${GEOTIFF_OPTIONS} ${2}.asc ${2}
   rm ${2}.{asc,prj}
}

function download_varanl {
   for file in ${REMOTE_FILES[@]}
   do
	   indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT count(granule) from ${WORKSPACE}.varanl_granules where granule='${file}'"`;
      if [ "${indexed}" = "0" ]; then 
      	ogrinfo -q PG:"host=${PG_HOST} user=docker password=docker dbname=wfas port=${PG_PORT}" \
		-sql "INSERT into ${WORKSPACE}.varanl_granules values('${file}')"
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
   
   for file in ${PCP_FILES[@]}
   do
	   indexed=`psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "SELECT count(granule) from ${WORKSPACE}.pcp_granules where granule='${file}'"`;
      if [ "${indexed}" = "0" ]; then
      	wget  -q --cut-dirs 6 -xnH -c --directory-prefix=${1} -N  --no-parent \
   	   ${RTMA_FTP}/${file}
      	ogrinfo -q PG:"host=${PG_HOST} user=docker password=docker dbname=wfas port=${PG_PORT}" \
		-sql "INSERT into ${WORKSPACE}.pcp_granules values('${file}')"
      fi
   done
}

function get_remote_files {
#Build a list of files on the ftp server:
for d in `curl -s --list-only ${RTMA_FTP}/|grep "^${FTP_DIR_PATTERN}"|sort` #a list of directories from ftp
do 
	for f in `curl -s --list-only ${RTMA_FTP}/${d}/ | grep "${FTP_FILE_PATTERN}$"|sort` #list varanl files in each directory
	do 
		REMOTE_FILES+=(`echo ${d}/${f}`) #add element to array
	done
done
}

function download_data {
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
}


function process_new_granules {

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
      f=`echo ${i}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
      if [ ! -f ${FILE_DIR}/tif/${var}/${f} ]; then
        dirname=`echo ${i}|rev|cut -d '/' -f 2|rev`
        mkdir -p ${FILE_DIR}/tif/${var}/${dirname}
	if [ ${DERIVED[${counter}]} = 1 ]; then
		${FUNCTION[${counter}]} ${i} ${FILE_DIR}/tif/${var}/${f}
	else
		gdal_translate -q -of GTiff -ot ${dtype} ${GEOTIFF_OPTIONS} -a_srs "${PROJ4_SRS}" \
			-b ${BAND[${counter}]} ${i} ${FILE_DIR}/tif/${var}/${f}
	fi
	find ${FILE_DIR}/tif/${var} -name '*.aux.xml' -delete
	#add new file to mosaic:
	curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XPOST \
		-H "Content-type: text/plain" -d "file://"${FILE_DIR}/tif/${var}/${f} \
	       	"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${var}/external.imagemosaic"
      fi
   done
   (( counter++ ))
done
}

function remove_old_granules {

counter=0

for var in ${VARS[@]}
do 
   FILE_DIR=${RTMA_DIR}/${EXTRACT_FROM[${counter}]}
   dataset=${EXTRACT_FROM[${counter}]}
   RETENTION_PERIOD_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`date +%Y-%m-%dT%H:%M:%SZ\`-"${RETENTION_PERIOD}"`
   filter="(time%20LT%20'${RETENTION_PERIOD_START}')"
   #Get a list of coverages for this mosaic, 
   #should be array with a single element:
   COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${var}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)
   c="${COVERAGES[0]}"
   #Sorted list of Mosaic granules:
   TO_DELETE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${var}/coverages/${c}/index/granules.xml?filter=${filter}" |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
   for i in ${TO_DELETE[@]}
   do
      #get last two tokens, containing dir and file name:
      f=`echo ${i}|rev|cut -d '/' -f 1,2|rev` #get last two tokens, containing dir and file name
      #delete the granule from mosaic:
      curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${var}/coverages/${c}/index/granules.xml?filter=location='${i}'"
      psql -A -t -h ${PG_HOST} -p${PG_PORT} -Udocker wfas -c "DELETE from ${WORKSPACE}.${dataset}_granules where granule='${f}'";
      #remove from file system
      rm -f ${i}
   done

   #Remove empty directories:
   find ${FILE_DIR}/tif/${var} -empty -type d -name "${FILE_PREFIX}.*" -delete
   (( counter++ ))
done
}

function clean_up {
for d in ${DATASETS[@]}
do 
   #RTMA grib files local storage locations:
   FILE_DIR=${RTMA_DIR}/${d}
   #Remove GRIB files:
   find ${FILE_DIR}/grb -type f -name '*grb*' -delete
   #Remove empty directories:
   find ${FILE_DIR}/grb -empty -type d -name "${FTP_DIR_PATTERN}.*" -delete
done
}

