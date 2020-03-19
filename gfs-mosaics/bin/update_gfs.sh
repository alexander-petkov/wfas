#!/bin/bash
export PATH=/opt/anaconda3/bin:/opt/anaconda3/condabin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="gfs"
GFS_DIR='/mnt/cephfs/wfas/data/gfs'
DATASETS=('UGRD'  'VGRD'  'APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WSPD' 'SOLAR') 
DERIVED=(0 0 0 0 0 0 1 1 1) #is the dataset downloaded, or derived from other variables?
FUNCTION=('' '' '' '' '' '' 'derive_wdir' 'derive_wspd' 'compute_solar') 
LEVEL=('10_m_above_ground' '10_m_above_ground' 'surface' '2_m_above_ground' 'entire_atmosphere' '2_m_above_ground' 'surface')

counter=0 

#NOMADS setup:
RES='0p25' #quarter-degree resolution
NOMADS_URL="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_${RES}_1hr.pl"
HOUR='t00z' #forecast hour
SUBREGION='subregion=&leftlon=-140&rightlon=-60&toplat=53&bottomlat=22'
#get latest forecast run:
FORECAST=`curl -s -l https://nomads.ncep.noaa.gov/pub/data/nccf/com/gfs/prod/|cut -d '"' -f 2|cut -d '/' -f 1|grep 'gfs\.'|tail -n 1`
#END NOMADS Setup

#GDAL exports:
export GRIB_NORMALIZE_UNITS=no #keep original units
export GDAL_DATA=/mnt/cephfs/gdal_data

#Windninja data:
export WINDNINJA_DATA=/mnt/cephfs/wfas/bin

function derive_wdir {
   for h in `seq -w 003 1 384`
   do 
      cdo -O expr,'10wdir=((10u<0)) ? 360+10u:10u;' -mulc,57.3 -atan2 -mulc,-1 \
	      ${GFS_DIR}/UGRD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc -mulc,-1 \
	      ${GFS_DIR}/VGRD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc \
	      ${GFS_DIR}/WDIR/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc
      t=`cdo -s showtimestamp -seltimestep,1 ${GFS_DIR}/WDIR/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc`
      date=`date  -d $t +'%Y%m%d%H%M'` 
      gdal_translate -of GTiff -co PROFILE=GeoTIFF -a_srs wgs84 -b 1 ${GFS_DIR}/WDIR/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc \
	      ${GFS_DIR}/WDIR/${date}.tif
   done
}
function derive_wspd {
   for h in `seq -w 003 1 384`
   do
      cdo -O -expr,'10si=(sqrt(10u*10u+10v*10v))' -merge ${GFS_DIR}/UGRD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc ${GFS_DIR}/VGRD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc ${GFS_DIR}/WSPD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc
      t=`cdo -s showtimestamp -seltimestep,1 ${GFS_DIR}/WSPD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc`
      date=`date  -d $t +'%Y%m%d%H%M'` 
      gdal_translate -of GTiff -co PROFILE=GeoTIFF -a_srs wgs84 ${GFS_DIR}/WSPD/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc \
	      ${GFS_DIR}/WSPD/${date}.tif
   done
}
function compute_solar {
   ELEV_FILE=/mnt/cephfs/wfas/data/gfs/gfs_dem.tif
   for cloud_file in ${GFS_DIR}/TCDC/tif/*.tif
   do
      filename=$(basename ${cloud_file} .tif)
      minute=${filename: -2}
      hour=${filename:8:2}
      day=${filename:6:2}
      month=${filename:4:2}
      year=${filename:0:4}
      /mnt/cephfs/wfas/bin/solar_grid --cloud-file ${cloud_file} \
	      --num-threads 4 --day ${day} --month ${month} \
	      --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
	      ${ELEV_FILE} ${GFS_DIR}/${1}/${filename}.asc
      gdal_translate -q -ot Int16 -of GTiff -co 'NUM_THREADS=ALL_CPUS' -co 'PROFILE=GeoTIFF' \
	      -co 'TILED=YES' -co 'NUM_THREADS=ALL_CPUS' \
	      ${GFS_DIR}/${1}/${filename}.asc ${GFS_DIR}/${1}/${filename}.tif
      rm ${GFS_DIR}/${1}/${filename}.{asc,prj}
   done
}
function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml" \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   echo ${c}
	   curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml"
	done
}

#Download GFS datasets
#and derive GTiff files:
for d in ${DATASETS[@]}
do 
   #GFS files local storage locations:
   FILE_DIR=${GFS_DIR}/${d}
   #Sync to the most current GFS forecast run at 00
   #Unless we have a derived dataset, 
   #in which case we calculate it:
#1. If dataset is not derived, get data
   if [ ${DERIVED[$counter]} = 0 ]; then 
      for h in `seq -w 003 1 384`
      do 
         wget  -q "${NOMADS_URL}?file=gfs.${HOUR}.pgrb2.${RES}.f${h}&lev_${LEVEL[$counter]}=on&var_${d}=on&${SUBREGION}&dir=%2F${FORECAST}%2F00" \
		-O ${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.tmp;
	 
	 #rewrite the grid from 0-360 to -180 180 lon range:
         cdo -f nc setgrid,${GFS_DIR}/mygrid -copy ${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.tmp \
		${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc;
         t=`cdo -s showtimestamp -seltimestep,1 ${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc`
         date=`date -d ${t} +'%Y%m%d%H%M'` 
         gdal_translate -of GTiff -co PROFILE=GeoTIFF -co COMPRESS=DEFLATE \
		-a_srs wgs84 -b 1 ${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.tmp \
		${FILE_DIR}/${date}.tif
      done
   elif [ ${DERIVED[$counter]} = 1 ]; then #derive dataset:
      ${FUNCTION[counter]} ${d} #execute corresponding derive function
   fi
   
   (( counter++ ))
done

#Files are downloaded 
#and new GTiff granules derived 
#in previous loop.
#Now update mosaics:
for d in ${DATASETS[@]}
do 
#1. Clear old granules from Geoserver's catalog and file system:
   #GFS files local storage locations:
   FILE_DIR=${GFS_DIR}/${d}
   #remove granules from mosaic catalog:
   remove_files_from_mosaic ${d}
   #remove old granules from system:
   rm  ${FILE_DIR}/tif/*.tif*
   find ${FILE_DIR} -empty -type f -delete ;
   rm ${FILE_DIR}/*.tmp ;
   rm ${FILE_DIR}/*.nc ;
#2. Move new granules in place:
   mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
#3.Re-index mosaic:
   curl -v -u admin:geoserver -H "Content-type: text/plain" -d "file://${GFS_DIR}/${d}/tif"  "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic"
done
