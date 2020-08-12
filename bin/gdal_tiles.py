import os
import sys
import osr
import gdal
import math

def get_extent(dataset):

    cols = dataset.RasterXSize
    rows = dataset.RasterYSize
    transform = dataset.GetGeoTransform()
    minx = transform[0]
    maxx = transform[0] + cols * transform[1] + rows * transform[2]

    miny = transform[3] + cols * transform[4] + rows * transform[5]
    maxy = transform[3]

    return {
            "minX": str(minx), "maxX": str(maxx),
            "minY": str(miny), "maxY": str(maxy),
            "cols": str(cols), "rows": str(rows)
            }

def create_tiles(minx, miny, maxx, maxy, n):
    width = maxx - minx
    height = maxy - miny

    matrix = []

    for j in range(n, 0, -1):
        for i in range(0, n):

            ulx = minx + (width/n) * i # 10/5 * 1
            uly = miny + (height/n) * j # 10/5 * 1

            lrx = minx + (width/n) * (i + 1)
            lry = miny + (height/n) * (j - 1)
            matrix.append([[ulx, uly], [lrx, lry]])

    return matrix


def split(file_name, n):
    raw_file_name = os.path.splitext(os.path.basename(file_name))[0].replace("_downsample", "")
    raw_file_name = os.path.basename(file_name) 
    driver = gdal.GetDriverByName('GRIB')
    dataset = gdal.Open(file_name)
    band = dataset.GetRasterBand(3)
    transform = dataset.GetGeoTransform()

    extent = get_extent(dataset)

    cols = int(extent["cols"])
    rows = int(extent["rows"])

    print ("Columns: ", cols)
    print ("Rows: ", rows)

    minx = float(extent["minX"])
    maxx = float(extent["maxX"])
    miny = float(extent["minY"])
    maxy = float(extent["maxY"])

    width = maxx - minx
    height = maxy - miny

    output_path = os.path.join("data", os.path.split(os.path.split(file_name)[0])[1] + '/' + raw_file_name)
    if not os.path.exists(output_path):
        os.makedirs(output_path)
    print (round(width,0),round(height, 0))
    print ("GCD", math.gcd(int(round(width, 0)), int(round(height, 0))))
    print ("Width", width)
    print ("height", height)


    tiles = create_tiles(minx, miny, maxx, maxy, n)
    transform = dataset.GetGeoTransform()
    xOrigin = transform[0]
    yOrigin = transform[3]
    pixelWidth = transform[1]
    pixelHeight = -transform[5]

    print (xOrigin, yOrigin)

    tile_num = 0
    for tile in tiles:

        minx = tile[0][0]
        maxx = tile[1][0]
        miny = tile[1][1]
        maxy = tile[0][1]

        p1 = (minx, maxy)
        p2 = (maxx, miny)

        i1 = int((p1[0] - xOrigin) / pixelWidth)
        j1 = int((yOrigin - p1[1])  / pixelHeight)
        i2 = int((p2[0] - xOrigin) / pixelWidth)
        j2 = int((yOrigin - p2[1]) / pixelHeight)

        print (i1, j1)
        print (i2, j2)

        new_cols = i2-i1
        new_rows = j2-j1

        data = band.ReadAsArray(i1, j1, new_cols, new_rows)

        #print data

        new_x = xOrigin + i1*pixelWidth
        new_y = yOrigin - j1*pixelHeight

        print (new_x, new_y)

        new_transform = (new_x, transform[1], transform[2], new_y, transform[4], transform[5])

        output_file_base = raw_file_name + "_" + str(tile_num) + ".tif"
        output_file = os.path.join("data", os.path.split(os.path.split(file_name)[0])[1]+ '/'+ raw_file_name, output_file_base)
        driver = gdal.GetDriverByName('GTiff')
        dst_ds = driver.Create(output_file,
                               new_cols,
                               new_rows,
                               1,
                               gdal.GDT_Int16,
			       options=['TILED=YES','BLOCKXSIZE=128','BLOCKYSIZE=128', 'COMPRESS=DEFLATE'])

        #writting output raster
        dst_ds.GetRasterBand(1).WriteArray( data )

        tif_metadata = {
            "minX": str(minx), "maxX": str(maxx),
            "minY": str(miny), "maxY": str(maxy)
        }
        dst_ds.SetMetadata(tif_metadata)

        #setting extension of output raster
        # top left x, w-e pixel resolution, rotation, top left y, rotation, n-s pixel resolution
        dst_ds.SetGeoTransform(new_transform)

        wkt = dataset.GetProjection()
        # setting spatial reference of output raster
        srs = osr.SpatialReference()
        srs.ImportFromProj4('+proj=lcc +lat_1=25 +lat_2=25 +lat_0=25 +lon_0=-95 +x_0=0 +y_0=0 +a=6371200 +b=6371200 +units=m +no_defs')
        #srs.SetAttrValue("CENTRAL_MERIDIAN",-95)
        print (srs.ExportToProj4())
        dst_ds.SetProjection( srs.ExportToWkt() )

        #Close output raster dataset
        dst_ds = None

        tile_num += 1

    dataset = None

split(sys.argv[1],int(sys.argv[2]))
