#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/rtma_common.sh

WORKSPACE="rtma"
RTMA_DIR=${DATA_DIR}/rtma
RTMA_FTP='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod'
FTP_DIR_PATTERN="rtma2p5"
FTP_FILE_PATTERN="varanl_ndfd.grb2_wexp"
REMOTE_FILES=() #initially empty array
DATASETS=('varanl' 'pcp')
FILE_PREFIX="rtma2p5"
PATTERNS=('rtma2p5.*.2dvaranl_ndfd.grb2_wexp' 'rtma2p5.*.pcp.184.grb2' 'rtma2p5.*.2dvaranl_ndfd.grb2_wexp')
VARS=('2t' 'tcc' 'tp' '10si' '10wdir' '2r' 'solar')
DERIVED=(0 0 0 0 0 1 1)
FUNCTION=('' '' '' '' '' 'derive_rhm' 'compute_solar')
EXTRACT_FROM=('varanl' 'varanl' 'pcp' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 13 1 9 8 0 0)
PROJ4_SRS='+proj=lcc +lat_0=25 +lon_0=-95 +lat_1=25 +lat_2=25 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

RETENTION_PERIOD="6 weeks"

ELEV_FILE=${RTMA_DIR}/${WORKSPACE}_dem.tif

get_remote_files
#printf '%s\n' ${REMOTE_FILES[@]}
download_data
process_new_granules
remove_old_granules
clean_up
${MOUNT_DIR}/wfas/bin/netcdf_package_export.sh archive=rtma starttime="`date +'%Y-%m-%dT00:00:00Z' -d '-1 day'`"
exit 0
