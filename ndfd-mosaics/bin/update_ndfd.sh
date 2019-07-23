#!/bin/bash
FTP_ADDR="ftp://tgftp.nws.noaa.gov/SL.us008001/ST.opnl/DF.gr2/DC.ndfd/AR.conus/"
REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="ndfd"

#NDFD grib files local storage locations:
NDFD_DIR='/mnt/cephfs/wfas/data/ndfd'

VARS=('temp' 'rhm' 'qpf' 'pop12' 'wspd' 'wdir' 'sky')
REMOTE_DIR=('VP.001-003' 'VP.004-007')
for v in ${VARS[@]}
do 
   #check that directories exist in $FILE_DIR:
   if [[ ! -e $NDFD_DIR/${v} ]]; then
      mkdir $NDFD_DIR/${v}
   fi
	
   for r in ${REMOTE_DIR[@]}
   do
      if curl -I ${FTP_ADDR}/${r}/ds.${v}.bin; then #check that remote file exists
         #update *.bin files from ftp:
         wget --cut-dirs 5 -A*${v}.bin -N -nH --recursive ${FTP_ADDR}/${r}/ \
            -O ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ;
	
	 #get coverage name(s) for this variable:
	 COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/coverages.xml \
		|grep -oP '(?<=<name>).*?(?=</name>)'`)	
	 
	 #remove existing granules from this variable's mosaic:
         for c in ${COVERAGES[@]}
         do
	     curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/coverages/${c}/index/granules.xml?filter=location='${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb'" ;
	done

	#now add the newly downloaded file to the mosaic:  
	curl -s -u admin:geoserver -XPOST -H "Content-type: text/plain" \
		-d "file://${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb" \
		"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/external.imagemosaic" ;       
      fi
   done
done

