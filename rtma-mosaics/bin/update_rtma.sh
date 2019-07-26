#!/bin/bash

REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="rtma"
DATASETS=('varanl' 'pcp')
PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp' 'rtma2p5.*.pcp.184.grb2')
counter=0

function add_new_files_to_mosaic {
for c in ${CUR_FILES[@]}
do
   found=0
   for m in ${MOSAIC_FILES[@]}
   do
      if [ "$c" = "$m" ]; then
         found=1 
         break
      fi
   done
   if [ $found = 0 ]; then 
      #add granule to mosaic:
      echo "Adding granule:" $c
      curl -s -u admin:geoserver -XPOST -H "Content-type: text/plain" -d "file://"$c "${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/external.imagemosaic"
   fi
done
}

function remove_file_from_mosaic {
   for c in ${COVERAGES[@]}
   do
	#get granule id	for this file:
        echo "Should delete granule:" ${1}
	#delete the granule:
	curl -s -u admin:geoserver -XDELETE "${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages/${c}/index/granules.xml?filter=location='${1}'"
   done
}

#loop over RTMA datasets:
for d in ${DATASETS[@]}
do 
   RTMA_MOSAIC="rtma_"${d}
   #RTMA grib files local storage locations:
   FILE_DIR='/mnt/cephfs/wfas/data/rtma/'${d}

   #Sync to the most current RTMA FTP archive: 
   wget -q --cut-dirs 6 -xnH -c --recursive --directory-prefix=$FILE_DIR -N  --no-parent \
	-A${PATTERNS[counter]} \
	ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/rtma2p5.*

   #Get a list of coverages for this mosaic:
   COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)
   #Sorted list of locally stored Grib files:
   CUR_FILES=(`find ${FILE_DIR} -name ${PATTERNS[counter]} |sort`)

   #Sorted list of Mosaic granules:
   MOSAIC_FILES=`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages/${COVERAGES[0]}/index/granules.xml |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`

   add_new_files_to_mosaic 

   for i in ${MOSAIC_FILES[@]}
   do 
      echo $f
      if ! curl -I ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/$f; then
         #remove old granules from the mosaic:
	 remove_file_from_mosaic $i
         #remove old granule from system:
         subdir=`echo ${i}|cut -d '/' -f 8`
         to_delete=`echo ${i}|cut -d '/' -f 9` #extract filename
         rm -rf $FILE_DIR/$subdir/*${to_delete}*
         rm -rf $FILE_DIR/$subdir/.${to_delete}*
      else
         break;
      fi;
   done

   #Remove empty directories:
   find ${FILE_DIR} -empty -type d -name 'rtma2p5.*' -delete
   (( counter++ ))
done
