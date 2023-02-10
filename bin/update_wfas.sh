#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

REMOTE_ADDR="https://www.wfas.net/data/ndfd/"
WORKSPACE="wfas"

#Local storage locations:
WFAS_DIR=${DATA_DIR}/wfas

VARS=('erc' 'bi' 'fbx' 'fm1000')
EXT=('_perc_new' '_perc_new' '_new' '')

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	IFS=$'\n' COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   encoded=$(python -c "from urllib.parse import quote; print(quote('''$c'''))")
	   #delete all granules:
	   curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${encoded}/index/granules.xml"
	done
}

function download_data {
   for d in `seq 0 6`
   do
      #check that remote file exists
      if curl -s -I ${REMOTE_ADDR}/${1}_day${d}${EXT[${counter}]}.tif; then 
         wget -q -N ${REMOTE_ADDR}/${1}_day${d}${EXT[${counter}]}.tif \
            -P ${WFAS_DIR}/${1} ;
	 modified=`stat ${WFAS_DIR}/${1}/${1}_day${d}${EXT[${counter}]}.tif |grep Modify|cut -d ' ' -f 2`
         date=`date +'%Y%m%d' -d "${modified} +"${d}" days"`
	 gdalwarp -t_srs EPSG:4326 ${WFAS_DIR}/${1}/${1}_day${d}${EXT[${counter}]}.tif \
		 ${WFAS_DIR}/${1}/${1}_${date}.tif
	 rm ${WFAS_DIR}/${1}/${1}_day${d}${EXT[${counter}]}.tif
      fi
   done
}
counter=0
for v in ${VARS[@]}
do 
   #check that directories exist in $FILE_DIR:
   if [[ ! -e $WFAS_DIR/${v} ]]; then
      mkdir -p $WFAS_DIR/${v}/tif
   fi
   
   rm $WFAS_DIR/${v}/*.tif

   download_data ${v}
 
   new_files=`ls ${WFAS_DIR}/${v}/${v}_*.tif|wc -l`
   if [ ${new_files} = 7 ]; then
	echo "New files: ${new_files}"
   	remove_files_from_mosaic ${v}
   	#remove geotiffs from previous forecast:
   	rm ${WFAS_DIR}/${v}/tif/*.tif*
	mv ${WFAS_DIR}/${v}/${v}_*.tif ${WFAS_DIR}/${v}/tif/.
	#build new .vrt file:
	gdalbuildvrt -separate -o ${WFAS_DIR}/${v}/${v}.vrt \
		${WFAS_DIR}/${v}/tif/*.tif
  	#now reindex the mosaic:  
   	for file in `ls ${WFAS_DIR}/${v}/tif/*.tif`
   		do
		curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XPOST -H "Content-type: text/plain" \
			-d "file://${file}" \
			"${REST_URL}/${WORKSPACE}/coveragestores/${v}/external.imagemosaic" ;       
  	 done
   fi
   (( counter++ ))
done

