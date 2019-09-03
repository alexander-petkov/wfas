#!/bin/bash

REST_URL="http://192.168.59.56:8081/geoserver/rest"
WORKSPACE="gfs"
GFS_DIR='/mnt/cephfs/wfas/data/gfs'
DATASETS=('APCP'  'RH'  'TCDC'  'TMP'  'UGRD'  'VGRD'  'WDIR'  'WSPD') 
DERIVED=(0 0 0 0 0 0 1 1) #is the dataset downloaded, or derived from other variables?
FUNCTION=('' '' '' '' '' '' 'derive_wdir' 'derive_wspd') 
LEVEL=('surface' '2_m_above_ground' 'entire_atmosphere' '2_m_above_ground' '10_m_above_ground' '10_m_above_ground')

counter=0 

#cdo-related setup:
export LD_LIBRARY_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/lib
export ECCODES_DEFINITION_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/share/eccodes/definitions
export ECCODES_SAMPLES_PATH=/mnt/cephfs/wfas/bin/eccodes-2.12.5/build/share/eccodes/samples
CDO_DIR='/mnt/cephfs/wfas/bin/cdo-1.9.7.1/src'

#NOMADS setup:
RES='0p50' #half-deegree resolution
NOMADS_URL="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_${RES}.pl"
SUBREGION='subregion=&leftlon=220&rightlon=290.84&toplat=53&bottomlat=22'
#get latest forecast run:
FORECAST=`curl -s -l https://nomads.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/|cut -d '"' -f 2|cut -d '/' -f 1|grep 'gfs\.'|tail -n 1`
#END NOMADS Setup

function derive_wdir {
   for h in `seq -w 003 3 384`
   do 
	${CDO_DIR}/cdo -O mulc,57.3 -atan2 -mulc,-1 ${GFS_DIR}/UGRD/gfs.t00z.pgrb2full.${RES}.f${h}.grb2 -mulc,-1 ${GFS_DIR}/VGRD/gfs.t00z.pgrb2full.${res}.f${h}.grb2 ${GFS_DIR}/WDIR/gfs.t00z.pgrb2full.${RES}.f${h}.grb2
   done
}
function derive_wspd {
   for h in `seq -w 003 3 384`
   do 
      ${CDO_DIR}/cdo -O select,name=10u,10v ${GFS_DIR}/UGRD/gfs.t00z.pgrb2full.${RES}.f${h}.grb2 ${GFS_DIR}/VGRD/gfs.t00z.pgrb2full.${RES}.f${h}.grb2 ${GFS_DIR}/out.grb2;
      ${CDO_DIR}/cdo -O expr,'10si=(sqrt(10u*10u+10v*10v))' ${GFS_DIR}/out.grb2 ${GFS_DIR}/WSPD/gfs.t00z.pgrb2full.${RES}.f${h}.grb2
   done
   rm -f ${GFS_DIR}/out.grb2
}

#loop over GFS datasets:
for d in ${DATASETS[@]}
do 
   #GFS grib files local storage locations:
   FILE_DIR=${GFS_DIR}/${d}

   #Sync to the most current GFS forecast run at 00
   #Unless we have a derived dataset, 
   #in which case we calculate it:
#1. If dataset is not derived, get data
   if [ ${DERIVED[$counter]} = 0 ]; then 
      for h in `seq -w 003 3 384`
      do 
         wget -q "${NOMADS_URL}?file=gfs.t00z.pgrb2full.${RES}.f${h}&lev_${LEVEL[$counter]}=on&var_${d}=on&${SUBREGION}&dir=%2F${FORECAST}%2F00" \
		-O ${FILE_DIR}/gfs.t00z.pgrb2full.${RES}.f${h}.grb2;
      done
   elif [ ${DERIVED[$counter]} = 1 ]; then #derive dataset:
      ${FUNCTION[counter]} #execute corresponding derive function
   fi
#2. update mosaic:
   curl -v -u admin:geoserver -H "Content-type: text/plain" -d "file://${GFS_DIR}/${d}"  "${REST_URL}/workspaces/${WORKSPACE}/coveragestores/${d}/external.imagemosaic"
   (( counter++ ))
done
