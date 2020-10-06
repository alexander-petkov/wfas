#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/globals.env

DROUGHT_DIR=${DATA_DIR}/shapefiles/drought
SHAPEFILES=(
	https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_current_M.zip
	)   
for s in ${SHAPEFILES[@]}
do 
#1. Download archive:
   wget -q -c -N -nd -nH -P ${DROUGHT_DIR} $s
   SHAPEFILE=`echo $s|rev|cut -d '/' -f 1|rev`
   unzip -qq -e -o ${DROUGHT_DIR}/${SHAPEFILE} -d ${DROUGHT_DIR}
   rm -rf ${DROUGHT_DIR}/*.zip
   for f in ${DROUGHT_DIR}/*
   do 
	   ext=`echo ${f}|cut -d '.' -f 2-`;
	   name=`basename ${f} .${ext}`;
	   rename='USDM';
	   mv ${f} ${DROUGHT_DIR}/${rename}.${ext};
   done
done
