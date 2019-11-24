#!/bin/bash
export PATH=/opt/anaconda3/bin:/opt/anaconda3/condabin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
FTP_ADDR="ftp://tgftp.nws.noaa.gov/SL.us008001/ST.opnl/DF.gr2/DC.ndfd/AR.conus"
REST_URL="http://192.168.59.56:8081/geoserver/rest/workspaces"
WORKSPACE="ndfd"

#NDFD grib files local storage locations:
NDFD_DIR='/mnt/cephfs/wfas/data/ndfd'

VARS=('temp' 'rhm' 'qpf' 'wspd' 'wdir' 'sky' 'pop12')
#REMOTE_DIR=('VP.001-003' 'VP.004-007')
REMOTE_DIR=('VP.001-003')
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

#GDAL exports:
export GRIB_NORMALIZE_UNITS=no #keep original units

function make_geotiffs {
	TIFF_PATH=`echo ${1}|rev|cut -d '/' -f 3-|rev`/tif
	band=1
	for t in `cdo showtimestamp ${1}`
	do
		if [ ${2} = 'qpf' ] ; then #derive hourly data
			hours=5
			while (( $hours >= 0 ))
			do 
				#subtract 0-5 hours from selected timestamp:
				d=`date --date="@$(($(date -d ${t} +%s) - $hours*3600))" +'%Y%m%d%H%M'`;
				gdal_calc.py --quiet -A ${1} --A_band=${band} --format=GTiff --co='PROFILE=GeoTIFF' \
					-co='TILED=YES' --calc='A/6' --outfile=${TIFF_PATH}/${d}.tif ;
				gdal_edit.py -a_srs "${PROJ4_SRS}" ${TIFF_PATH}/${d}.tif ;
				((hours--));
			done 
		else
			d=`date  -d $t +'%Y%m%d%H%M'`;
			gdal_translate -q -of GTiff -co 'PROFILE=GeoTIFF' -co 'TILED=YES' -a_srs "${PROJ4_SRS}" \
			--config CENTER_LONG -95 -b ${band} \
			${1} ${TIFF_PATH}/${d}.tif 
		fi
		((band++))
	done
}

function remove_old_geotiffs {
	TIFF_PATH=`echo ${1}|rev|cut -d '/' -f 3-|rev`/tif
	rm ${TIFF_PATH}/*.tif*
	#for t in `cdo showtimestamp ${1}`
	#do
#		d=`date  -d $t +'%Y%m%d%H%M'`;
#		rm ${TIFF_PATH}/${d}.tif
#	done
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
      mkdir -p $NDFD_DIR/${v}
   fi

   remove_files_from_mosaic ${v}
   #remove geotiffs generated from previous forecast:
   rm ${NDFD_DIR}/${v}/tif/*.tif*
   
   for r in ${REMOTE_DIR[@]}
   do
      if curl -I ${FTP_ADDR}/${r}/ds.${v}.bin; then #check that remote file exists
        
	 #update *.bin files from ftp:
         wget --cut-dirs 5 -A*${v}.bin -N -nH --recursive ${FTP_ADDR}/${r}/ \
            -O ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ;

 	 make_geotiffs ${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb ${v};
	 
	 #get coverage name(s) for this variable:
	 #COVERAGES=(`curl -s -u admin:geoserver -XGET ${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/coverages.xml \
	 #	|grep -oP '(?<=<name>).*?(?=</name>)'`)	
	 
	 #remove existing granules from this variable's mosaic:
         #for c in ${COVERAGES[@]}
         #do
	 #    curl -s -u admin:geoserver -XDELETE \
	 #	"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/coverages/${c}/index/granules.xml?filter=location='${NDFD_DIR}/${v}/${r}/ds.${v}.bin.grb'" ;
	 #done

	#now reindex the mosaic:  
	for file in `ls ${NDFD_DIR}/${v}/tif/*.tif`
	do
		curl -s -u admin:geoserver -XPOST -H "Content-type: text/plain" \
			-d "file://${file}" \
			"${REST_URL}/${WORKSPACE}/coveragestores/${WORKSPACE}_${v}/external.imagemosaic" ;       
	done
      fi
   done
done

