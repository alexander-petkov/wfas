#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

FTP_ADDR="ftp://tgftp.nws.noaa.gov/SL.us008001/ST.opnl/DF.gr2/DC.ndfd/AR.conus"
WORKSPACE="ndfd"

#NDFD grib files local storage locations:
NDFD_DIR=${DATA_DIR}/ndfd

VARS=('temp' 'rhm' 'qpf' 'wspd' 'wdir' 'sky' 'pop12' 'solar')
#REMOTE_DIR=('VP.001-003' 'VP.004-007')
REMOTE_DIR=('VP.001-003')
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

function make_geotiffs {
	TIFF_PATH=`echo ${1}|rev|cut -d '/' -f 3-|rev`/tif
	band=1
	for t in `cdo -s showtimestamp ${1}`
	do
		if [ ${2} = 'qpf' ] ; then #derive hourly data
			hours=5
			while (( $hours >= 0 ))
			do 
				#subtract 0-5 hours from selected timestamp:
				d=`date --date="@$(($(date -d ${t} +%s) - $hours*3600))" +'%Y%m%d%H%M'`;
				gdal_calc.py --quiet -A ${1} --A_band=${band} --format=GTiff ${GDAL_CALC_OPTIONS} \
					--calc='A/6' --outfile=${TIFF_PATH}/${d}.tif ;
				gdal_edit.py -a_srs "${PROJ4_SRS}" ${TIFF_PATH}/${d}.tif ;
				((hours--));
			done 
		else
			d=`date  -d $t +'%Y%m%d%H%M'`;
			gdal_translate -q -of GTiff ${GEOTIFF_OPTIONS} -a_srs "${PROJ4_SRS}" \
				--config CENTER_LONG -95 -b ${band} ${1} ${TIFF_PATH}/${d}.tif 
		fi
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
      rm ${NDFD_DIR}/${1}/tif/${filename}.{asc,prj}
   done
}
function remove_old_geotiffs {
	TIFF_PATH=`echo ${1}|rev|cut -d '/' -f 3-|rev`/tif
	rm ${TIFF_PATH}/*.tif*
}

function remove_files_from_mosaic {
	#Get a list of coverages for this mosaic:
	COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/ndfd_${1}/coverages.xml \
		                     |grep -oP '(?<=<name>).*?(?=</name>)'`)
	for c in ${COVERAGES[@]}
	do
	   #delete all granules:
	   curl -s -u admin:geoserver -XDELETE \
		"${REST_URL}/${WORKSPACE}/coveragestores/ndfd_${1}/coverages/${c}/index/granules.xml"
	done
}

for v in ${VARS[@]}
do 
   #check that directories exist in $FILE_DIR:
   if [[ ! -e $NDFD_DIR/${v} ]]; then
      mkdir -p $NDFD_DIR/${v}/tif
   fi

   remove_files_from_mosaic ${v}
   #remove geotiffs generated from previous forecast:
   rm ${NDFD_DIR}/${v}/tif/*.tif*
   
   for r in ${REMOTE_DIR[@]}
   do
      if curl -s -I ${FTP_ADDR}/${r}/ds.${v}.bin; then #check that remote file exists
        
	 #update *.bin files from ftp:
         #wget --cut-dirs 5 -A*${v}.bin -N -nH --recursive ${FTP_ADDR}/${r}/ \
         wget -q -N ${FTP_ADDR}/${r}/ds.${v}.bin \
            -O ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ;

 	 make_geotiffs ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ${v};
      fi
   done
   if [ ${v} = 'solar' ]; then
	compute_solar ${v}
   fi
   #now reindex the mosaic:  
   for file in `ls ${NDFD_DIR}/${v}/tif/*.tif`
   do
	curl -s -u admin:geoserver -XPOST -H "Content-type: text/plain" \
		-d "file://${file}" \
		"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/external.imagemosaic" ;       
   done
done

