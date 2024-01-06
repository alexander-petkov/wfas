#!/mnt/cephfs/miniconda3/bin/python3
#import cgitb; cgitb.enable()
import numpy as np
from osgeo import gdal, ogr,osr
import fiona
import rasterio
from fiona import transform
from pprint import pprint
from shapely.geometry import shape, Polygon, Point
from rasterstats import zonal_stats, point_query
import readline
import json 
import cgi
import logging
import glob
from regions import regions

def str2bool(v):
  return v.lower() in ("yes", "true", "t", "1")

def geomFromBounds(bounds, srs_wkt):
    ring = ogr.Geometry(ogr.wkbLinearRing)
    ring.AddPoint(bounds[0], bounds[1])
    ring.AddPoint(bounds[0], bounds[3])
    ring.AddPoint(bounds[2], bounds[3])
    ring.AddPoint(bounds[2], bounds[1])
    ring.AddPoint(bounds[0], bounds[1])

    poly = ogr.Geometry(ogr.wkbPolygon)
    poly.AddGeometry(ring)
    crs = osr.SpatialReference()
    crs.ImportFromWkt(srs_wkt)
    poly.AssignSpatialReference(crs)
    return poly

def deleteKeys(dic, pattern):
    list_keys = list(dic.keys())
    for k in list_keys:
        if k.startswith(pattern):
            dic.pop(k)

def myconverter(obj):
        if isinstance(obj, np.integer):
            return int(obj)
        elif isinstance(obj, np.floating):
            return float(obj)
        elif isinstance(obj, np.ndarray):
            return obj.tolist()
        elif isinstance(obj, datetime.datetime):
            return obj.__str__()

def to_dict (keys,values,bin_edges,percent):
    #counts, vals = ndarray
    res = {}
    if (bin_edges is not None):
        for i in range(1,len(bin_edges)) :
            if (bin_edges[i]-1==bin_edges[i-1]):
                key = str(bin_edges[i-1])
                bool_mask = (keys==bin_edges[i-1])
            else:
                if (i<len(bin_edges)-1):
                    key = str(bin_edges[i-1]) + '-' + str(bin_edges[i]-1)
                    bool_mask = (keys>=bin_edges[i-1]) & (keys<=bin_edges[i]-1)
                else:
                    key = str(bin_edges[i-1]) + '-' + str(bin_edges[i])
                    bool_mask = (keys>=bin_edges[i-1]) & (keys<=bin_edges[i])

            value = int(sum(values[bool_mask]))
            if (bool(percent)):
                #value= round(value/sum(values),2)
                value= round((value/sum(values))*100,2)
            if (value>0):
                res[key] = value
            
    else: #return whole histogram as a dictionary, without binning
        for i in range(len(keys)) :
            key = str(keys[i])
            value = values[i]
            if (bool(percent)):
                #value= round(value/sum(values),2)
                value= round((value/sum(values))*100,2)
            res[key] = value
    
    return res

#1. parse cgi arguments:
form = cgi.FieldStorage()
bins = None
percent = False
erc=bi=sfdi = False
erc_rast=bi_rast=sfdi_rast = {}

#get url path for input json
if 'zoneurl' in form:
    zoneurl=form.getvalue('zoneurl')
else:
   print("Argument zoneurl is required for this script to run, exiting...")

if 'bins' in form:
    bins = int(form.getvalue('bins'))

if 'percent' in form:
    percent=str2bool(form.getvalue('percent'))

if 'erc' in form:
    erc=str2bool(form.getvalue('erc'))

if 'bi' in form:
    bi=str2bool(form.getvalue('bi'))

if 'sfdi' in form:
    sfdi=str2bool(form.getvalue('sfdi'))

c= fiona.open(zoneurl,'r')
#Construct an OGR geometry from 
bounds =  c.bounds
coll_env = geomFromBounds(bounds, c.crs_wkt)

within = False
region = {} 
r = 0

for r in range(len(regions)):
    region = list(regions.values())[r]
    raster = rasterio.open(region.get("Landform"))
    rast_env = geomFromBounds(raster.bounds,raster.crs.to_wkt())
    # create the CoordinateTransformation
    coordTrans = osr.CoordinateTransformation(coll_env.GetSpatialReference(), 
                                              rast_env.GetSpatialReference())
    coll_env.Transform(coordTrans)
    if (rast_env.Contains(coll_env)):
        within = True
        break

if (within == False):
    region = {}
    print("We do not have raster data for this zone collection.")
    exit(0)

if (erc != True ) :
    deleteKeys(region, "ERC")
    #erc_rast  = {'ERC Day ' + str(i) : v
    #        for i,v in
    #            enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/erc/tif*.tif"),start=1)}

if (bi != True ) :
    deleteKeys(region,"BI")
    #bi_rast   = {'BI Day ' + str(i) : v
    #        for i,v in
    #            enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/bi/tif/*.tif"),start=1)}
if (sfdi != True ) :
    deleteKeys(region,"SFDI")
    #sfdi_rast  = {'SFDI Day ' + str(i) : v
    #        for i,v in
    #            enumerate(glob.glob("/mnt/cephfs/wfas/data/wfas/fdx/tif/*.tif"),start=1)}

rasters = {'Elevation': '/data/landfire/CONUS/US_DEM_2016_02192019/Grid/us_dem_2016_tiled.tiff',
        'Landform' : '/data/ergeo/USA_Landform_30m_WMAS.tif',
        'Slope' : '/data/ergeo/US_SLOPE_PERCENT_16bit.tif',
        **erc_rast,
        **bi_rast,
        **sfdi_rast,
           }
rasters=region

results=[]

for zone in c.items():
    lon = zone[1]['properties']['longitude']
    lat = zone[1]['properties']['latitude']
    keys = list(rasters.keys())
    for k in range(len(keys)):
        r= gdal.Open(rasters[keys[k]])
        raster_proj = osr.SpatialReference(wkt=r.GetProjection())
        if ( isinstance(lon ,float) and
            isinstance(lat ,float)) : 
            pt = transform.transform(c.crs,raster_proj.ExportToProj4(),
                [lon],[lat])
            repr_p= Point(pt[0][0],pt[1][0])
        repr_zone=transform.transform_geom(c.crs,
                raster_proj.ExportToProj4(),
                zone[1]['geometry'])
        point_val = point_query(repr_p, rasters[keys[k]])
        zs =  zonal_stats([repr_zone], rasters[keys[k]],stats=['min', 'max', 'mean', 'median','count','unique'], all_touched=True)
        zhist= zonal_stats([repr_zone],
                rasters[keys[k]],
                categorical=True,all_touched=True)[0]
        k1=np.fromiter(zhist.keys(),dtype='int')
        v1=np.fromiter(zhist.values(),dtype='int')
        bin_edges = None 
        if bins is not None and k1.size>0:
            if (bins<k1.size) :
                seq = np.arange(zs[0]['min'],zs[0]['max']+1,1)
                bin_edges=np.histogram_bin_edges(seq,bins=bins).astype('int')
        hist = to_dict(k1,v1,bin_edges,percent)
        res ={'Origin'   : point_val[0],
            'Min'    : zs[0]['min'],
            'Max'    : zs[0]['max'],
            'Mean'   : zs[0]['mean'],
            'Median' : zs[0]['median'],
            'Count' : zs[0]['count'],
            'Hist' : hist
            }
        zone[1]['properties'][keys[k]] = res
    results.append(zone[1])

results2= {"type":"FeatureCollection","features": results}
print ('Content-Type: application/json\n');
print ()
print(json.dumps(results2,default=myconverter))
c.close()
