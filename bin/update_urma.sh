#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/urma_common.sh

WORKSPACE="urma"
URMA_DIR=${DATA_DIR}/${WORKSPACE}
FTP_DIR='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/urma/prod'
FTP_DIR_PATTERN="urma2p5\."
FTP_FILE_PATTERN="varanl_ndfd.grb2_wexp"
REMOTE_FILES=() #initially empty array
DATASETS=('varanl' 'pcp')
FILE_PREFIX="urma2p5"
PATTERNS=('urma2p5.*.2dvaranl_ndfd.grb2_wexp' 'urma2p5.*.pcp.01h.wexp.grb2')
VARS=('2t' 'tp' '10si' '10wdir' '2r' 'solar')
DERIVED=(0 0 0 0 1 1)
FUNCTION=('' '' '' '' 'derive_rhm' 'compute_solar')
EXTRACT_FROM=('varanl' 'pcp' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 1 9 8 0 14)
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

RETENTION_PERIOD="6 weeks"

ELEV_FILE=${URMA_DIR}/${WORKSPACE}_dem.tif

get_remote_files
download_data
process_new_granules
remove_old_granules
clean_up
${MOUNT_DIR}/wfas/bin/netcdf_package_export.sh archive=urma starttime="`date +'%Y-%m-%dT00:00:00Z' -d '-1 day'`" >> ${MOUNT_DIR}/netcdf/netcdf_export.log 2>&1
exit 0
