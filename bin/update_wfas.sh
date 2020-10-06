#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

REMOTE_ADDR="https://www.wfas.net/data/ndfd/"
WORKSPACE="wfas"

#Local storage locations:
WFAS_DIR=${DATA_DIR}/wfas

VARS=('erc' 'bi' 'fbx')
EXT=('perc_new' 'perc_new' 'new')

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml"
	done
}
counter=0
for v in ${VARS[@]}
do 
   #check that directories exist in $FILE_DIR:
   if [[ ! -e $WFAS_DIR/${v} ]]; then
      mkdir -p $WFAS_DIR/${v}/tif
   fi

   remove_files_from_mosaic ${v}
   #remove geotiffs from previous forecast:
   rm ${WFAS_DIR}/${v}/tif/*.tif*
   
   for d in `seq 0 6`
   do
      if curl -s -I ${REMOTE_ADDR}/${v}_day${d}_${EXT[${counter}]}.tif; then #check that remote file exists
         date=`date +'%Y%m%d' -d '+'${d}' days'`
         wget -q -N ${REMOTE_ADDR}/${v}_day${d}_${EXT[${counter}]}.tif \
            -O ${WFAS_DIR}/${v}/tif/${v}${date}.tif ;
      fi
   done
   #now reindex the mosaic:  
   for file in `ls ${WFAS_DIR}/${v}/tif/*.tif`
   do
	curl -s -u admin:geoserver -XPOST -H "Content-type: text/plain" \
		-d "file://${file}" \
		"${REST_URL}/${WORKSPACE}/coveragestores/${v}/external.imagemosaic" ;       
   done
   (( counter++ ))
done

