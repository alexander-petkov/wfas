#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/rtma_common.sh

WORKSPACE="rtma_ak"
RTMA_DIR=${DATA_DIR}/rtma/AK
RTMA_FTP='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/rtma/prod/'
FTP_DIR_PATTERN="akrtma"
FTP_FILE_PATTERN="2dvaranl_ndfd_3p0.grb2"
REMOTE_FILES=() #initially empty array
DATASETS=('varanl')
PATTERNS=('akrtma.t??z.2dvaranl_ndfd_3p0.grb2')
VARS=('2t' 'tcc' '10si' '10wdir' '2r' 'solar')
DERIVED=(0 0 0 0 1 1)
FUNCTION=('' '' '' '' 'derive_rhm' 'compute_solar')
EXTRACT_FROM=('varanl' 'varanl' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 13 9 8 0 0)
PROJ4_SRS='+proj=stere +lat_0=90 +lat_ts=60 +lon_0=-150 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

ELEV_FILE=${RTMA_DIR}/rtma_dem_ak.tif

get_remote_files
download_data
process_new_granules
remove_old_granules
clean_up
exit 0
