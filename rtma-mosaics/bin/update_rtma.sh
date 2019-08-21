#!/bin/bash

REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="rtma"
RTMA_DIR='/mnt/cephfs/wfas/data/rtma'
DATASETS=('varanl' 'pcp' 'rhm')
PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp' 'rtma2p5.*.pcp.184.grb2' 'rtma2p5.*.2dvaranl_ndfd.grb2_wexp')
#DATASETS=('rhm')
#PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp')
counter=0

#cdo-related setup:
export LD_LIBRARY_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/lib
export ECCODES_DEFINITION_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/share/eccodes/definitions
export ECCODES_SAMPLES_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/share/eccodes/samples

function derive_rhm {
   for src in `find ${RTMA_DIR}/varanl -name '*_wexp' |sort`
   do
     f=`echo ${src}|cut -d '/' -f 8-`
     if [ ! -f ${RTMA_DIR}/rhm/${f} ]; then
       dirname=`echo ${src}|cut -d '/' -f 8`
       mkdir -p ${RTMA_DIR}/rhm/${dirname}      
       /mnt/cephfs/wfas/bin/cdo-1.9.7.1/src/cdo \
		-expr,'2r=(exp(1.81+(2d*17.27- 4717.31) / (2d - 35.86))/exp(1.81+(2t*17.27- 4717.31) / (2t - 35.86)))*100' \
		${src} ${RTMA_DIR}/rhm/$f
     fi
   done
}		      
	
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
   FILE_DIR=${RTMA_DIR}/${d}

   #Sync to the most current RTMA FTP archive
   #Unless we have the Rel Humidity (rhm) dataset, 
   #which is derived from varanl data:
   if [ ! ${d} = 'rhm' ] ; then
      wget -q --cut-dirs 6 -xnH -c --recursive --directory-prefix=$FILE_DIR -N  --no-parent \
	   -A${PATTERNS[counter]} \
	   ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/rtma2p5.*
   else
      derive_rhm
   fi

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
      f=`echo ${i}|cut -d '/' -f 8-` #get last two tokens, containing dir and file name
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
