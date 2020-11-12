#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/gfs_common.sh

WORKSPACE="gfs_sa"
GFS_DIR=${DATA_DIR}/gfs_sa
ELEV_FILE=${GFS_DIR}/gfs_sa_dem.tif
#Bolivia:
SUBREGION='subregion=&leftlon=-70&rightlon=-57&toplat=-10&bottomlat=-23'

download_data 

update_geoserver

