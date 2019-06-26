#!/bin/bash

REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="weather"
RTMA_MOSAIC="rtma_mosaic"

#RTMA grib files local storage locations:
FILE_DIR='/mnt/cephfs/wfas/data/rtma/met/grib/'

#Sync to the most current RTMA FTP archive: 
wget --cut-dirs 6 -xnH -c --recursive --directory-prefix=$FILE_DIR -N  --no-parent \
	-Artma2p5.*.2dvaranl_ndfd.grb2_wexp \
	ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/rtma2p5.*

#Get a list of RTMA coverages:
COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)

#List of locally stored Grib files:
CUR_FILES=(`find ${FILE_DIR} -name '*.2dvaranl_ndfd.grb2_wexp' |sort`)

#List of Mosaic granules:
MOSAIC_FILES=`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages/${COVERAGES[0]}/index/granules.xml |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'`

for c in ${CUR_FILES[@]}
do 
 found=0
 for m in ${MOSAIC_FILES[@]}
 do
   if [ "$c" = "$m" ]; then
     echo "Granule already in mosaic:" $c
     found=1 
     break
   fi
 done
 if [ $found = 0 ]; then 
   #add granule to mosaic:
   echo "Adding granule:" $c
   curl -v -u admin:geoserver -XPOST -H "Content-type: text/plain" -d "file:${c}" ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/external.imagemosaic
 fi
done    

function remove_file_from_mosaic {
   for c in ${COVERAGES[@]}
   do
	#get granule id	for this file:
	gran_id=`curl -s -uadmin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages/${c}/index/granules.xml?filter=location=%27${1}%27|grep -oP '(?<=<gf:'${c}' fid=").*?(?=">)'`
        echo "Should delete granule:" ${gran_id}
	#delete the granule, using the fid retrieved above:
	curl -s -u admin:geoserver -XDELETE "${REST_URL}/${WORKSPACE}/coveragestores/${RTMA_MOSAIC}/coverages/${c}/index/granules/${gran_id}"
   done
}

for i in ${CUR_FILES[@]}
do 
  f=`echo ${i}|cut -d '/' -f 9-`
  if ! curl -I ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/$f; then
    #remove old granules from the mosaic:
    remove_file_from_mosaic $i
    #remove old granule from system:
    subdir=`echo ${i}|cut -d '/' -f 9`
    to_delete=`echo ${i}|cut -d '/' -f 10` #extract filename
    rm -rf $FILE_DIR/$subdir/*${to_delete}*
  else
    break
  fi;
done

#Remove empty directories:
find ${FILE_DIR} -empty -type d -name 'rtma2p5.*' -delete

