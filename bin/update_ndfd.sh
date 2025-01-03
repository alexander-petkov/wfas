#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

FTP_ADDR="ftp://tgftp.nws.noaa.gov/SL.us008001/ST.opnl/DF.gr2/DC.ndfd/AR.conus"
WORKSPACE="ndfd"

#NDFD grib files local storage locations:
NDFD_DIR=${DATA_DIR}/ndfd

VARS=('temp' 'rhm' 'qpf' 'wspd' 'wdir' 'sky' 'pop12' 'solar')
REMOTE_DIR=('VP.001-003' 'VP.004-007')
#REMOTE_DIR=('VP.001-003')
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

#Build temporal filter:
RETENTION_PERIOD_START=`date +'%Y-%m-%dT%H:%M:%SZ' -d \`date +%Y-%m-%dT%H:%M:%SZ\`-"${RETENTION_PERIOD}"`
filter="(time%20LT%20'${RETENTION_PERIOD_START}')"
 
function reprojectWGS84 {
	gdalwarp -of GTiff ${GEOTIFF_OPTIONS} -t_srs WGS84 ${1} ${1}.wgs84
	rm ${1} ${1}.wgs84.aux.xml
	mv ${1}.wgs84 ${1}
	
}
function make_geotiffs {
	TIFF_PATH=`echo ${1}|rev|cut -d '/' -f 3-|rev`/tif
	band=1
	for t in `cdo -s showtimestamp ${1}`
	do
		t=`date -d ${t} +'%Y-%m-%dT%H:00:00'` #round date/time to top of the hour
		if [ ${2} = 'qpf' ] ; then #derive hourly data
			hours=5
			while (( $hours >= 0 ))
			do 
				#subtract 0-5 hours from selected timestamp:
				d=`date --date="@$(($(date -d ${t} +%s) - $hours*3600))" +'%Y%m%d%H%M'`;
				if [[ -e ${TIFF_PATH}/../../temp/tif/${d}.tif ]] ; then
					gdal_calc.py --overwrite --quiet -A ${1} --A_band=${band} \
						--format=GTiff ${GDAL_CALC_OPTIONS} \
						--calc='A/6' --outfile=${TIFF_PATH}/${d}.tif ;
					gdal_edit.py -a_srs "${PROJ4_SRS}" ${TIFF_PATH}/${d}.tif ;
				fi
				((hours--));
			done 
		else
			d=`date  -d $t +'%Y%m%d%H%M'`;
			gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${PROJ4_SRS}" \
				--config CENTER_LONG -95 -b ${band} ${1} ${TIFF_PATH}/${d}.tif 
		fi
		reprojectWGS84 ${TIFF_PATH}/${d}.tif
		rm ${TIFF_PATH}/${d}.tif.aux.xml
		((band++))
	done
}
function compute_solar {
   ELEV_FILE=${NDFD_DIR}/ndfd_dem.tif
   for cloud_file in ${NDFD_DIR}/sky/tif/*.tif
   do
      filename=$(basename ${cloud_file} .tif)
      minute=${filename: -2}
      hour=${filename:8:2}
      day=${filename:6:2}
      month=${filename:4:2}
      year=${filename:0:4}
      solar_grid --cloud-file ${cloud_file} \
	      --num-threads 6 --day ${day} --month ${month} \
	      --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
	      ${ELEV_FILE} ${NDFD_DIR}/${1}/tif/${filename}.asc
      gdal_translate -q -ot Int16 -of GTiff ${GEOTIFF_OPTIONS} \
	      ${NDFD_DIR}/${1}/tif/${filename}.asc ${NDFD_DIR}/${1}/tif/${filename}.tif
      rm ${NDFD_DIR}/${1}/tif/${filename}.{asc,prj,tif.aux.xml}
      reprojectWGS84 ${NDFD_DIR}/${1}/tif/${filename}.tif
   done
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages.xml \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #Sorted list of Mosaic granules to delete:
     	   TO_DELETE=(`curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} \
		   -XGET "${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${var}/coverages/${c}/index/granules.xml?filter=${filter}" \
		   |grep -oP '(?<=<gf:location>).*?(?=</gf:location>)'|sort`)
   	   for i in ${TO_DELETE[@]}
   	   do
	      curl -s -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/${1}/coverages/${c}/index/granules.xml?filter=location='${i}'"
	      #remove from file system
	      rm -f ${i}
           done
	done
}

for v in ${VARS[@]}
do 
   #check that directories exist in $FILE_DIR:
   if [[ ! -e $NDFD_DIR/${v} ]]; then
      mkdir -p $NDFD_DIR/${v}/tif
   fi
   
   for r in ${REMOTE_DIR[@]}
   do
      if curl -s -I ${FTP_ADDR}/${r}/ds.${v}.bin; then #check that remote file exists
        
	 #update *.bin files from ftp:
         wget -q -N ${FTP_ADDR}/${r}/ds.${v}.bin \
            -O ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ;

 	 make_geotiffs ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ${v};
      fi
   done
   if [ ${v} = 'solar' ]; then
	compute_solar ${v}
   fi

   remove_files_from_mosaic ${v}
   
   #now reindex the mosaic:  
   for file in `ls ${NDFD_DIR}/${v}/tif/*.tif`
   do
	curl -u ${GEOSERVER_USERNAME}:${GEOSERVER_PASSWORD} -XPOST -H "Content-type: text/plain" \
		-d "file://${file}" \
		"${REST_URL}/${WORKSPACE}/coveragestores/${v}/external.imagemosaic" ;       
   done
done

{MOUNT_DIR}/wfas/bin/netcdf_package_export.sh archive=ndfd
