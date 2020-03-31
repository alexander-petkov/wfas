#!/bin/bash

export PATH=/opt/anaconda3/bin:/opt/anaconda3/condabin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MOUNT_DIR='/mnt/cephfs'
NETCDF_OUTPUT_DIR=$MOUNT_DIR/netcdf/rtma
WFAS_BIN=$MOUNT_DIR/wfas/bin
RTMA_DATA_DIR=$MOUNT_DIR/wfas/data/rtma
VARANL_GRID=${RTMA_DATA_DIR}/varanl/varanl_grid
DATASETS=('varanl' 'pcp' 'rhm')
VARS=('2t' '2r' 'tp' '10si' '10wdir' 'tcc' 'solar') 
EXTRACT_FROM=('varanl' 'rhm' 'pcp' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 1 1 9 8 13 0)
counter=0

#GDAL exports:
export GRIB_NORMALIZE_UNITS=no #keep original units
export GDAL_DATA=$MOUNT_DIR/gdal_data

#Windninja data:
export WINDNINJA_DATA=$MOUNT_DIR/wfas/bin
ELEV_FILE=${RTMA_DATA_DIR}/rtma_dem.tif

function compute_solar_file {
   if [ -f ${1} ]; then
      minute=0
      hour=${1:68:2}
      day=${1:56:2}
      month=${1:54:2}
      year=${1:50:4}
      echo Year: ${year}, month: ${month}, day: ${day}, hour: ${hour}
      /mnt/cephfs/wfas/bin/solar_grid --cloud-file ${1} \
	      --num-threads 4 --day ${day} --month ${month} \
	      --year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
	      ${ELEV_FILE} ${2}.asc
      tail -n +7 ${2}.asc |tac | \
	      cdo -P 4 -f nc4 -settaxis,${year}-${month}-${day},${hour}:00:00,hours -setname,solar \
		-input,${VARANL_GRID}  ${2}.solar
      rm ${2}.{asc,prj}
   fi
}


#Get a list of directories with complete 24-hour Grib archive.
#This will result of repeating each element up to 3 times, 
#which are the directories we want.

FULLDIRS=(`find ${RTMA_DATA_DIR}/varanl/grb/ -type d -path '*rtma2p5*' \
		-exec bash -c 'if [ \`ls {}/*_wexp|wc -l\` = 24 ]; then echo {} |cut -d '/' -f 9 ; fi' \;` 
	  `find ${RTMA_DATA_DIR}/pcp/grb/ -type d -path '*rtma2p5*' \
		-exec bash -c 'if [ \`ls {}/*.grb2|wc -l\` = 24 ]; then echo {} |cut -d '/' -f 9 ; fi' \;` 
	  `find ${RTMA_DATA_DIR}/rhm/grb/ -type d -path '*rtma2p5*' \
		-exec bash -c 'if [ \`ls {}/*_wexp|wc -l\` = 24 ]; then echo {} |cut -d '/' -f 9 ; fi' \;`)
			 
FULLDIRS=(`printf '%s\n' "${FULLDIRS[@]}"|sort |uniq -c|grep '3 rtma'|cut -d ' ' -f 8`)
#loop over directories:
for d in ${FULLDIRS[@]}
do 
	mkdir -p ${NETCDF_OUTPUT_DIR}/${d}
	if [ ! -f ${NETCDF_OUTPUT_DIR}/${d}.nc ]; then
	   for f in `find ${RTMA_DATA_DIR}/varanl/tif/tcc/${d}/*_wexp`
	   do
		filename=`echo ${f}|rev|cut -d '/' -f 1|rev`
	   	compute_solar_file ${f} ${NETCDF_OUTPUT_DIR}/${d}/${filename}
		PCP_FILE=`echo ${d}/${filename}| \
			awk '{print substr($0,1,17) substr($0,1,8) substr($0,9,8) substr($0,27,2) ".pcp.184.grb2"}'`
		cdo -P 4 -f nc4  -merge -selname,2t,10wdir,10si ${RTMA_DATA_DIR}/varanl/grb/${d}/${filename} \
			-setgrid,${VARANL_GRID} -invertlat ${RTMA_DATA_DIR}/rhm/grb/${d}/${filename} \
			-remapycon,${VARANL_GRID} ${RTMA_DATA_DIR}/pcp/grb/${PCP_FILE}  \
			${NETCDF_OUTPUT_DIR}/${d}/${filename}.solar ${NETCDF_OUTPUT_DIR}/${d}/${filename}.nc
	   done
   	   #merge all files for this 24-hour period:
	   cdo -P 4 -f nc4 invertlat -setgatt,history,"merged all timesteps" -mergetime ${NETCDF_OUTPUT_DIR}/${d}/*.nc ${NETCDF_OUTPUT_DIR}/${d}.nc
	   #clean up:
	   #rm -rf ${NETCDF_OUTPUT_DIR}/${d}	   
	fi
done

