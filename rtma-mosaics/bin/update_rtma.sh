#!/bin/bash

REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="rtma"
RTMA_DIR='/mnt/cephfs/wfas/data/rtma'
DATASETS=('varanl' 'pcp' 'rhm')
PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp' 'rtma2p5.*.pcp.184.grb2' 'rtma2p5.*.2dvaranl_ndfd.grb2_wexp')
VARS=('2t' '2r' 'tp' '10si' '10wdir' 'tcc') 
EXTRACT_FROM=('varanl' 'rhm' 'pcp' 'varanl' 'varanl' 'varanl')
BAND=(3 1 1 9 8 13)
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'
counter=0

#GDAL exports:
export GRIB_NORMALIZE_UNITS=no #keep original units

function derive_rhm {
   for src in `find ${RTMA_DIR}/varanl/grb -name '*_wexp' |sort`
   do
     f=`echo ${src}|cut -d '/' -f 9-`
     if [ ! -f ${RTMA_DIR}/rhm/grb/${f} ]; then
       dirname=`echo ${src}|cut -d '/' -f 9`
       mkdir -p ${RTMA_DIR}/rhm/grb/${dirname}      
       cdo \
		-expr,'2r=(exp(1.81+(2d*17.27- 4717.31) / (2d - 35.86))/exp(1.81+(2t*17.27- 4717.31) / (2t - 35.86)))*100' \
		${src} ${RTMA_DIR}/rhm/grb/$f
     fi
   done
}		      

function remove_file_from_mosaic {
   #Get a list of coverages for this mosaic:
   COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/rtma_${1}/coverages.xml \
               |grep -oP '(?<=<name>).*?(?=</name>)'`)
   for c in ${COVERAGES[@]}
   do
      #delete the granule:
      curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/rtma_${1}/coverages/${c}/index/granules.xml?filter=location='${2}'"
   done
}

function download_varanl {
   wget -q --cut-dirs 6 -xnH -c --recursive --directory-prefix=${1} -N  --no-parent \
      -A${PATTERNS[counter]} \
      ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/rtma2p5.*
}

function download_pcp {
   #Rewrite downloaded varanl file names to pcp, and download only those.
   #This is to ensure that varanl and pcp archives are with aligned timesteps.
   PCP_FILES=(`find $RTMA_DIR/varanl/grb -name *wexp |cut -d '/' -f 9-|awk '{print substr($0,1,17) substr($0,1,8) substr($0,9,8) substr($0,27,2) ".pcp.184.grb2"}'|sort`)
   
   for f in ${PCP_FILES[@]}
   do
      wget -q --cut-dirs 6 -xnH -c --directory-prefix=${1} -N  --no-parent \
	   ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/${f}
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
      download_${d} $FILE_DIR/grb
   else
      derive_rhm
   fi
   
   #Sorted list of locally stored Grib files:
   CUR_FILES=(`find ${FILE_DIR}/grb -name ${PATTERNS[counter]} |sort`)
   for i in ${CUR_FILES[@]}
   do 
      f=`echo ${i}|cut -d '/' -f 9-` #get last two tokens, containing dir and file name
      
      if [ ${d} = 'pcp' ] ; then
	 #rewrite pcp file name to a coresponding time step varanl name,
         #so we keep pcp archive aligned with varanl in time
	 f=`echo ${f}|awk '{print substr($0,1,17) substr($0,18,7) ".t" substr($0,34,2) "z.2dvaranl_ndfd.grb2_wexp"}'`
      fi; 
     
      if ! curl -I ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/$f; then
         #remove old granule from system:
         subdir=`echo ${i}|cut -d '/' -f 9`
         to_delete=`echo ${i}|cut -d '/' -f 10` #extract filename
	 find $FILE_DIR/grb -path '*'$subdir/${to_delete} -delete
      else
         break;
      fi;
   done
   #Remove empty directories:
   find ${FILE_DIR}/grb -empty -type d -name 'rtma2p5.*' -delete
   (( counter++ ))
done

counter=0

for var in ${VARS[@]}
do 
   FILE_DIR=${RTMA_DIR}/${EXTRACT_FROM[${counter}]}
   #Sorted list of locally stored Grib files:
   CUR_FILES=(`find ${FILE_DIR}/grb -type f |sort`)

   for i in ${CUR_FILES[@]}
   do
      f=`echo ${i}|cut -d '/' -f 9-` #get last two tokens, containing dir and file name
      if [ ! -f ${FILE_DIR}/tif/${var}/${f} ]; then
        dirname=`echo ${i}|cut -d '/' -f 9`
        mkdir -p ${FILE_DIR}/tif/${var}/${dirname}
	gdal_translate -of GTiff -a_srs "${PROJ4_SRS}" -b ${BAND[${counter}]} ${i} ${FILE_DIR}/tif/${var}/${f}
	#add new file to mosaic:
	curl -s -u admin:geoserver -XPOST \
		-H "Content-type: text/plain" -d "file://"${FILE_DIR}/tif/${var}/${f} \
	       	"${REST_URL}/${WORKSPACE}/coveragestores/rtma_${var}/external.imagemosaic"
      fi
   done
   
   #remove any TIF files
   #not found in the local Grib  archive
   TIF_FILES=(`find ${FILE_DIR}/tif/${var} -path '*rtma2p5*' -type f |sort`)
   for i in ${TIF_FILES[@]}
   do
      f=`echo ${i}|cut -d '/' -f 10-` #get last two tokens, containing dir and file name
      if [ ! -f ${FILE_DIR}/grb/${f} ]; then
	#remove from mosaic
	remove_file_from_mosaic $var $i
	#remove from file system
	rm -f ${i}
      fi
   done

   #Remove empty directories:
   find ${FILE_DIR}/tif/${var} -empty -type d -name 'rtma2p5.*' -delete
   (( counter++ ))
done

