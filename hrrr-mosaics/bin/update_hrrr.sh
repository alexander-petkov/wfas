#!/bin/bash
export PATH=/opt/anaconda3/bin:/opt/anaconda3/condabin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="hrrr"
HRRR_DIR='/mnt/cephfs/wfas/data/hrrr'
FILENAME='hrrr.t00z.wrfsfcf'
HRRR_GRID=${HRRR_DIR}/hrrr_grid
DATASETS=('UGRD'  'VGRD'  'APCP'  'RH'  'TCDC'  'TMP'  'WDIR'  'WIND' 'DSWRF') 
DERIVED=(0 0 0 0 0 0 1 0 0) #is the dataset downloaded, or derived from other variables?
FUNCTION=('' '' '' '' '' '' 'derive_wdir' '' '') 
LEVEL=('10_m_above_ground' '10_m_above_ground' 'surface' '2_m_above_ground' 'entire_atmosphere' 
	'2_m_above_ground' '10_m_above_ground' '10_m_above_ground' 'surface') 

DATASETS=('WDIR') 
DERIVED=(1) #is the dataset downloaded, or derived from other variables?
FUNCTION=('derive_wdir') 
LEVEL=('10_m_above_ground')

counter=0 

#NOMADS setup:
#RES='0p25' #quarter-degree resolution
NOMADS_URL="https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl"
#HOUR='t00z' #forecast hour
SUBREGION='subregion=&leftlon=-140&rightlon=-60&toplat=53&bottomlat=22'
#get latest forecast run:
FORECAST=`curl -s -l https://nomads.ncep.noaa.gov/pub/data/nccf/com/hrrr/prod/|cut -d '"' -f 2|cut -d '/' -f 1|grep 'hrrr\.'|tail -n 1`
#END NOMADS Setup

#GDAL exports:
export GRIB_NORMALIZE_UNITS=no #keep original units
export GDAL_DATA=/mnt/cephfs/gdal_data
GEOTIFF_OPTIONS='-co PROFILE=GeoTIFF -co COMPRESS=DEFLATE -co TILED=YES -co NUM_THREADS=ALL_CPUS'
HRRR_PROJ='+proj=lcc +lat_1=38.5 +lat_2=38.5 +lat_0=38.5 +lon_0=-97.5 +x_0=0 +y_0=0 +a=6371229 +b=6371229 +units=m +no_defs '

#Windninja data:
export WINDNINJA_DATA=/mnt/cephfs/wfas/bin

function derive_wdir {
   for h in `seq -w 00 1 36`
   do 
      #cdo -s -O -P 4 -invertlat -expr,'10wdir=((10u<0)) ? 360+10u:10u;' -mulc,57.3 -atan2 -mulc,-1 \
	      #${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2 -mulc,-1 \
	      #${HRRR_DIR}/VGRD/${FILENAME}${h}.grib2 \
	      #${HRRR_DIR}/WDIR/${FILENAME}${h}.nc
      t=`cdo -s showtimestamp -seltimestep,1 ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2`
      date=`date  -d $t +'%Y%m%d%H%M'` 
      #gdal_translate -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" -b 1 ${HRRR_DIR}/WDIR/${FILENAME}${h}.nc \
	      #${HRRR_DIR}/WDIR/${date}.tif
      gdal_calc.py --quiet --format=GTiff -A ${HRRR_DIR}/UGRD/${FILENAME}${h}.grib2 -B ${HRRR_DIR}/VGRD/${FILENAME}${h}.grib2 \
		--A_band=1 --B_band=1 \
		--calc='where(57.3*arctan2(-1*A,-1*B)<0,360+(57.3*arctan2(-1*A,-1*B)),57.3*arctan2(-1*A,-1*B))' \
		--co=PROFILE=GeoTIFF --co=COMPRESS=DEFLATE --co=TILED=YES --co=NUM_THREADS=ALL_CPUS \
   		--outfile=${HRRR_DIR}/WDIR/${date}.tif
      gdal_edit.py -a_srs "${HRRR_PROJ}" ${HRRR_DIR}/WDIR/${date}.tif
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

#Download HRRR datasets
#and derive GTiff files:
for d in ${DATASETS[@]}
do 
   #HRRR files local storage locations:
   FILE_DIR=${HRRR_DIR}/${d}
   #Sync to the most current HRRR forecast run at 00
   #Unless we have a derived dataset, 
   #in which case we calculate it:
#1. If dataset is not derived, get data
   if [ ${DERIVED[$counter]} = 0 ]; then 
      for h in `seq -w 00 1 36`
      do 
         wget -q "${NOMADS_URL}?file=${FILENAME}${h}.grib2&lev_${LEVEL[$counter]}=on&var_${d}=on&${SUBREGION}&dir=%2F${FORECAST}%2Fconus" \
		-O ${FILE_DIR}/${FILENAME}${h}.grib2;
	 
	 #rewrite the grid from 0-360 to -180 180 lon range:
         #/cdo -f nc setgrid,${HRRR_DIR}/mygrid -copy ${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.tmp \
	#/	${FILE_DIR}/gfs.${HOUR}.pgrb2.${RES}.f${h}.nc;
         t=`cdo -s showtimestamp -seltimestep,1 ${FILE_DIR}/${FILENAME}${h}.grib2`
         date=`date -d ${t} +'%Y%m%d%H%M'` 
         gdal_translate -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${HRRR_PROJ}" \
		-b 1 ${FILE_DIR}/${FILENAME}${h}.grib2 \
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
   #HRRR files local storage locations:
   FILE_DIR=${HRRR_DIR}/${d}
   #remove granules from mosaic catalog:
   remove_files_from_mosaic ${d}
   #remove old granules from system:
   rm  ${FILE_DIR}/tif/*.tif*
   find ${FILE_DIR} -empty -type f -delete ;
   #/rm ${FILE_DIR}/*.tmp ;
   #/rm ${FILE_DIR}/*.nc ;
#2. Move new granules in place:
   mv ${FILE_DIR}/*.tif* ${FILE_DIR}/tif/.
#3.Re-index mosaic:
   find ${FILE_DIR}/tif -name '*.tif' -exec \
	   curl -s -u admin:geoserver -H "Content-type: text/plain" -d "file://"{}  \
	      "${REST_URL}/${WORKSPACE}/coveragestores/${d}/external.imagemosaic" \;
done
