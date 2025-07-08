#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/urma_common.sh

WORKSPACE="akurma"
URMA_DIR=${DATA_DIR}/akurma
FTP_DIR='ftp://ftp.ncep.noaa.gov/pub/data/nccf/com/urma/prod'
FTP_DIR_PATTERN="akurma\."
FTP_FILE_PATTERN="2dvaranl_ndfd_3p0.grb2"
REMOTE_FILES=() #initially empty array
DATASETS=('varanl')
PATTERNS=('akurma.t??z.2dvaranl_ndfd_3p0.grb2')
VARS=('2t' '10si' '10wdir' '2r' 'solar')
DERIVED=(0 0 0 1 1)
FUNCTION=('' '' '' 'derive_rhm' 'compute_solar')
EXTRACT_FROM=('varanl' 'varanl' 'varanl' 'varanl' 'varanl')
BAND=(3 9 8 0 14)
HAS_PRECIP=0
PROJ4_SRS='+proj=stere +lat_0=90 +lat_ts=60 +lon_0=-150 +x_0=0 +y_0=0 +R=6371200 +units=m +no_defs'

ELEV_FILE=${URMA_DIR}/urma_dem_ak.tif

function varanl2pcp {
   #extract dir name:
   d=`printf ${1}|cut -d '/' -f 1`
   #extract 2-digit hour:
   h=`printf ${1}|cut -d '.' -f 3 | awk '{print substr($0,2,2)}'`
   #construct pcp file name:
   pcp_file=`printf ${d}/pcpurma_ak${d}${h}".06h.grb2"`
}

get_remote_files
download_data
process_new_granules
#remove_old_granules
clean_up
exit 0
