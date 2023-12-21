import glob
erc_rast  = {'ERC Day ' + str(i) : v
            for i,v in
                enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/erc/tif/*.tif"),start=1)}

bi_rast   = {'BI Day ' + str(i) : v
            for i,v in
                enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/bi/tif/*.tif"),start=1)}
sfdi_rast  = {'SFDI Day ' + str(i) : v
            for i,v in
                enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/fbx/tif/*.tif"),start=1)}
                
conus = {'Elevation': '/data/landfire/CONUS/US_DEM_2016_02192019/Grid/us_dem_2016_tiled.tiff',
        'Landform' : '/data/ergeo/USA_Landform_30m_WMAS.tif',
        'Slope' : '/data/ergeo/US_SLOPE_PERCENT_16bit.tif',
        **erc_rast,
        **bi_rast,
        **sfdi_rast,
           }

erc  = {'ERC Day ' + str(i) : v 
            for i,v in 
                enumerate(glob.glob("/mnt/cephfs/wfas/data/gfs/netcdf/ercperc/tif/*.tif"),start=1)}
bi   = {'BI Day ' + str(i) : v 
            for i,v in 
                enumerate(glob.glob("/mnt/cephfs/wfas/data/gfs/netcdf/biperc/tif/*.tif"),start=1)}
sfdi  = {'SFDI Day ' + str(i) : v 
            for i,v in 
                enumerate(glob.glob("/mnt/cephfs/wfas/data/gfs/netcdf/sfdiperc/tif/*.tif"),start=1)}

sa = {'Elevation': '/mnt/cephfs/wfas/data/gmted/SouthAmerica_30arcsec_DEM_GMTED2010_Masked.tif',
        'Landform' : '/mnt/cephfs/wfas/data/sar/SA_Landforms_GEE.tif',
        'Slope' : '/mnt/cephfs/wfas/data/gmted/wfas_SouthAmerica_30arcsec_Slope_GMTED2010_Masked_WGS84.tif',
        **erc,
        **bi, 
        **sfdi
       }

regions = {"CONUS": conus, "South America": sa}
