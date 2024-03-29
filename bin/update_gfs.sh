#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/gfs_common.sh

WORKSPACE="gfs"
GFS_DIR=${DATA_DIR}/gfs
ELEV_FILE=${GFS_DIR}/gfs_dem.tif
ELEV_FILE=${GFS_DIR}/aster_dem.tif
#CONUS extent:
SUBREGION='subregion=&leftlon=-140&rightlon=-60&toplat=53&bottomlat=22'
#GLOBAL extent:
SUBREGION='subregion=&leftlon=-180&rightlon=180&toplat=90&bottomlat=-90'

download_data
update_geoserver
exit 0
