#!/bin/bash

#get the path for this script:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source ${DIR}/gfs_common.sh

WORKSPACE="gfs_sa"
GFS_DIR=${DATA_DIR}/gfs_sa
ELEV_FILE=${GFS_DIR}/gfs_sa_dem.tif
#Bolivia:
SUBREGION='subregion=&leftlon=-70&rightlon=-57&toplat=-10&bottomlat=-23'
#Extend to include  Colombia, Peru, Brazil, and Ecuador:
SUBREGION='subregion=&leftlon=-81.6&rightlon=-34.2&toplat=13&bottomlat=-35.3'

download_data 

update_geoserver

