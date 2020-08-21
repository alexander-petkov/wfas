#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

NETCDF_OUTPUT_DIR=$MOUNT_DIR/netcdf/rtma
RTMA_DATA_DIR=$MOUNT_DIR/wfas/data/rtma
VARANL_GRID=${RTMA_DATA_DIR}/varanl/varanl_grid

#Windninja data:
ELEV_FILE=${RTMA_DATA_DIR}/rtma_dem.tif

function compute_solar_file {
   if [ -f ${1} ]; then
      minute=0
      hour=${1:68:2}
      day=${1:56:2}
      month=${1:54:2}
      year=${1:50:4}
      echo Year: ${year}, month: ${month}, day: ${day}, hour: ${hour}
      solar_grid --cloud-file ${1} \
	--num-threads 4 --day ${day} --month ${month} \
	--year ${year} --minute ${minute} --hour ${hour} --time-zone UTC \
	${ELEV_FILE} ${2}.asc
      tail -n +7 ${2}.asc |tac | \
	 cdo -P 4 -f nc4 -settaxis,${year}-${month}-${day},${hour}:00:00,hours -setname,solar \
	   -input,${VARANL_GRID}  ${2}.solar
      rm ${2}.{asc,prj}
   fi
}

function compute_rhm {
   dirname=`echo ${2}|rev|cut -d '/' -f 2|rev`
   filename=`echo ${2}|rev|cut -d '/' -f 1|rev`
   grib_file=`find ${RTMA_DATA_DIR}/varanl/grb/${dirname} -name ${filename}`
   if [ -f ${grib_file} ]; then
      cdo -s invertlat \
         -expr,'2r=(exp(1.81+(2d*17.27- 4717.31) / (2d - 35.86))/exp(1.81+(2t*17.27- 4717.31) / (2t - 35.86)))*100' \
         ${grib_file} ${2}.rhm
   fi
}

#Get a list of directories with complete 24-hour Grib archive.
#This will result of repeating each element 2 times, 
#which are the directories we want.

FULLDIRS=(`find ${RTMA_DATA_DIR}/varanl/grb/ -type d -path '*rtma2p5*' \
		-exec bash -c 'if [ \`ls {}/*_wexp|wc -l\` = 24 ]; then echo {} |cut -d '/' -f 9 ; fi' \;` 
	  `find ${RTMA_DATA_DIR}/pcp/grb/ -type d -path '*rtma2p5*' \
		-exec bash -c 'if [ \`ls {}/*.grb2|wc -l\` = 24 ]; then echo {} |cut -d '/' -f 9 ; fi' \;`)
			 
FULLDIRS=(`printf '%s\n' "${FULLDIRS[@]}"|sort |uniq -c|grep '2 rtma'|cut -d ' ' -f 8`)
#loop over directories:
echo Array length: ${#FULLDIRS[@]}
echo 1st ellement: ${FULLDIRS[0]}
for d in ${FULLDIRS[$((${#FULLDIRS[@]}-1))]}
do 
	if [ ! -f ${NETCDF_OUTPUT_DIR}/${d}.nc ]; then
	   mkdir -p ${NETCDF_OUTPUT_DIR}/${d}
	   for f in `find ${RTMA_DATA_DIR}/varanl/tif/tcc/${d}/*_wexp`
	   do
		filename=`echo ${f}|rev|cut -d '/' -f 1|rev`
	   	compute_solar_file ${f} ${NETCDF_OUTPUT_DIR}/${d}/${filename}
	   	compute_rhm ${f} ${NETCDF_OUTPUT_DIR}/${d}/${filename}
		PCP_FILE=`echo ${d}/${filename}| \
			awk '{print substr($0,1,17) substr($0,1,8) substr($0,9,8) substr($0,27,2) ".pcp.184.grb2"}'`
		cdo -P 4 -f nc4  -merge -setgrid,${VARANL_GRID} -selname,2t,10wdir,10si \
			${RTMA_DATA_DIR}/varanl/grb/${d}/${filename} \
			-setgrid,${VARANL_GRID} -invertlat ${NETCDF_OUTPUT_DIR}/${d}/${filename}.rhm \
			-remapycon,${VARANL_GRID} ${RTMA_DATA_DIR}/pcp/grb/${PCP_FILE}  \
			${NETCDF_OUTPUT_DIR}/${d}/${filename}.solar ${NETCDF_OUTPUT_DIR}/${d}/${filename}.nc
	   done
   	   #merge all files for this 24-hour period:
	   cdo -P 4 -f nc4 -setgatt,history,"merged all timesteps" \
		   -mergetime ${NETCDF_OUTPUT_DIR}/${d}/*.nc ${NETCDF_OUTPUT_DIR}/${d}.nc
	   #clean up:
	   rm -rf ${NETCDF_OUTPUT_DIR}/${d}	   
	fi
done

