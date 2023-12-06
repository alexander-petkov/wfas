package org.geoserver.wfas.wps;

import java.awt.image.DataBuffer;
import java.io.File;
import java.io.IOException;
import java.net.MalformedURLException;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.logging.Logger;

import org.geoserver.catalog.Catalog;
import org.geoserver.catalog.CoverageInfo;
import org.geotools.coverage.grid.GridCoverage2D;
import org.geotools.coverage.grid.io.AbstractGridFormat;
import org.geotools.coverage.processing.CoverageProcessor;
import org.geotools.api.data.DataSourceException;
import org.geotools.data.DataUtilities;
import org.geotools.data.crs.ForceCoordinateSystemFeatureResults;
import org.geotools.data.simple.SimpleFeatureCollection;
import org.geotools.data.simple.SimpleFeatureIterator;
import org.geotools.data.store.ReprojectingFeatureCollection;
import org.geotools.feature.SchemaException;
import org.geotools.feature.simple.SimpleFeatureBuilder;
import org.geotools.feature.simple.SimpleFeatureTypeBuilder;
import org.geotools.gce.geotiff.GeoTiffFormat;
import org.geotools.gce.geotiff.GeoTiffReader;
import org.geotools.geometry.jts.JTS;
import org.geotools.geometry.jts.ReferencedEnvelope;
import org.geotools.process.factory.DescribeParameter;
import org.geotools.process.factory.DescribeProcess;
import org.geotools.process.factory.DescribeResult;
import org.geotools.process.raster.RasterZonalStatistics;
import org.geotools.process.raster.RasterZonalStatistics2;
import org.geotools.referencing.CRS;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.Point;
import org.geotools.api.coverage.grid.GridCoverageWriter;
import org.geotools.api.feature.simple.SimpleFeature;
import org.geotools.api.feature.simple.SimpleFeatureType;
import org.geotools.api.geometry.MismatchedDimensionException;
import org.geotools.api.parameter.GeneralParameterValue;
import org.geotools.api.referencing.FactoryException;
import org.geotools.api.referencing.NoSuchAuthorityCodeException;
import org.geotools.api.referencing.crs.CoordinateReferenceSystem;
import org.geotools.api.referencing.operation.TransformException;

import it.geosolutions.jaiext.range.RangeFactory;
import it.geosolutions.jaiext.stats.Statistics;
import it.geosolutions.jaiext.stats.Statistics.StatsType;
import it.geosolutions.jaiext.zonal.ZoneGeometry; 

/**
 * A process computing zonal statistics based on a raster data set and a set of polygonal zones of
 * interest
 *
 * @author Andrea Antonello (www.hydrologis.com)
 * @author Emanuele Tajariol (GeoSolutions)
 * @author Andrea Aime - GeoSolutions
 */
@DescribeProcess(
    title = "Raster Zonal Statistics",
    description =
            "Computes statistics for the distribution of a certain quantity in a set of polygonal zones."
)
public class WildfireZonalStatistics extends WFASProcess {

	    private static final CoverageProcessor PROCESSOR = CoverageProcessor.getInstance();
	    private static final Logger LOGGER = Logger.getLogger(WildfireZonalStatistics.class.toString());
	    //private String GEOSERVER_URL = "http://localhost:8080/geoserver";
	    private String GEOSERVER_URL = "https://aws.wfas.net:443/geoserver";
	    		
	    private String[][] coverageNames = {{"Elevation", "landfire","us_dem_2016"},
	    		{"Landform", "wfas", "USA_Landform_30m_WMAS"},
	    		{"Slope", "landfire","us_slpd_2016_tiled"}};
	    StatsType[] def =
                new StatsType[] {
                		StatsType.MIN,
                        StatsType.MAX,
                        StatsType.MEAN,
                        StatsType.MEDIAN,
                        StatsType.HISTOGRAM
                };
	    /**
	     * Comparator for sorting ingested
	     * features by ID
	     */
	    Comparator<SimpleFeature> compareById = new Comparator<SimpleFeature>() {
	    	@Override
	    	public int compare(SimpleFeature o1, SimpleFeature o2) {
	    		/*OK for now, but use
	    		 *o1.getID() if there is no OBJECTID field
	    		 *in other datasets
	    		 */

	    		return (new Long(o1.getAttribute("OBJECTID").toString()))
	    				.compareTo(new Long(o2.getAttribute("OBJECTID").toString()));
	    	}
	    };
	    /**
		 * Default constructor
		 */
		public WildfireZonalStatistics(Catalog catalog) {
			super(catalog);
		}
	    @DescribeResult(
	        name = "statistics",
	        description =
	                "A feature collection with the attributes of the zone layer (prefixed by 'z_') and the statistics fields count,min,max,sum,avg,stddev"
	    )
	    public SimpleFeatureCollection execute(
	            @DescribeParameter(
	                        name = "zones",
	                        description = "Zone polygon features for which to compute statistics"
	                    )
	                    SimpleFeatureCollection zones ) throws IOException, NoSuchAuthorityCodeException, FactoryException{

	        if ( zones.getSchema().getCoordinateReferenceSystem()==null) {
	        	try {
					zones = new ForceCoordinateSystemFeatureResults(zones, CRS.decode("EPSG:4326"), false);
				} catch (IOException | SchemaException | FactoryException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}
	        }
	        
            CoordinateReferenceSystem inputCRS=zones.getBounds().getCoordinateReferenceSystem();
            
            SimpleFeatureType ourFeatureType = buildFeatureTypeforStats(zones);
            SimpleFeatureBuilder sfb = new SimpleFeatureBuilder(ourFeatureType);

            List<SimpleFeature> tmpList = new ArrayList<SimpleFeature>();
            SimpleFeatureIterator sfi = zones.features();
            
            while(sfi.hasNext()) {
            	SimpleFeature s = sfi.next();
            	tmpList.add(sfb.buildFeature(s.getID(), s.getProperties().toArray()));
            }
            
            tmpList.sort(compareById);
            sfi.close();
            
            for (SimpleFeature curZone: tmpList) {
            	double lon=0, lat=0;
            	try {
            		lon = (double)curZone.getAttribute("longitude");
                	lat = (double)curZone.getAttribute("latitude");
            	}catch (ClassCastException cce) {
            		cce.printStackTrace();
            		LOGGER.fine("Longitude: " + curZone.getAttribute("longitude").toString());
            		LOGGER.fine("Latitude: " + curZone.getAttribute("latitude").toString());
            	}
            	Point fireOrigin = createPoint(lon,lat);
            	for (int i=0;i<coverageNames.length;i++) {
            		CoverageInfo covInfo = catalog.getCoverageByName(coverageNames[i][1], coverageNames[i][2]);
            
            		Map<String,Object> m = new HashMap<String, Object>();	
            		fireOrigin = transformPoint(fireOrigin, covInfo.getCRS());
            		String res = getFeatureInfo(covInfo, fireOrigin);
            		m.put("Origin", res==null?Double.NaN:Double.valueOf(res));
            		
            		/**
            		 * 2. Read in a cropped version of this coverage, 
            		 * by constructing a getCoverage URL. 
            		 * This is to utilize other Geoserver nodes. 
            		 */
            		Geometry zoneGeom = transformGeometry((Geometry)curZone.getDefaultGeometry(), inputCRS, covInfo.getCRS());
            		LOGGER.info("Geometry with OBJECTID " + curZone.getAttribute("OBJECTID") + 
            				" is within coverage: " + isWithinCoverage(zoneGeom, covInfo));
            		
            		Coordinate[] coords = zoneGeom.getEnvelope().getCoordinates();
            		double x_pad = 0.25*Math.abs(coords[2].x-coords[0].x);
            		double y_pad = 0.25*Math.abs(coords[2].y-coords[0].y);
            		URL zoneCoverageURL = new URL(GEOSERVER_URL +
            				"/wcs?SERVICE=WCS" +
            				"&REQUEST=GetCoverage" + 
            				"&VERSION=2.0.1" + 
            				"&CoverageId=" + coverageNames[i][1] + ":" + coverageNames[i][2] + 
            				"&SUBSETTINGCRS=" + covInfo.getCRS().getIdentifiers().toArray()[0] +
            				"&SUBSET=X(" + (coords[0].x-x_pad) + "," + (coords[2].x + x_pad) + ")" +
            				"&SUBSET=Y(" + (coords[0].y-y_pad) + "," + (coords[2].y+y_pad) + ")" + 
            				"&format=image/tiff");
            		
            		GridCoverage2D gc = getCroppedCoverage(zoneCoverageURL);
            		/**
            		 *  we can  write it down
            		 *  if uncomment the code below:
            		 */
            		try {
            			
            			writeToFile(gc, "/tmp/" + coverageNames[i][0] +
                        		curZone.getAttribute("OBJECTID").toString() + 
                        		".tif");
            		}catch (NullPointerException npe) {
            			LOGGER.finest(npe.getMessage());
            		}
            		
            		SimpleFeatureCollection curZoneCollection = DataUtilities.collection(curZone);
            		if (!curZone.getBounds()
            				.getCoordinateReferenceSystem()
            					.equals(covInfo.getCRS())) {
            			curZoneCollection = new ReprojectingFeatureCollection(curZoneCollection,
            					covInfo.getCRS());
            		}
	
            		if(gc!=null
            				&& isWithinCoverage(zoneGeom, gc)) {   
            			//find min/max/avg/median
                		RasterZonalStatistics rzs = new RasterZonalStatistics();
                		SimpleFeatureCollection statFeatures = rzs.execute(gc, 0, curZoneCollection, null);
                		SimpleFeature statFeature = statFeatures.features().next();
                		double croppedMinValue=(double)statFeature.getAttribute("min");
                		double croppedMaxValue=(double)statFeature.getAttribute("max");
                		
                		List<SimpleFeature> lsf = new ArrayList<SimpleFeature>();
                		lsf.add(curZoneCollection.features().next());
                		
                		RasterZonalStatistics2 rzs2 = new RasterZonalStatistics2();
                		try {
        					List<ZoneGeometry> rezults = rzs2.execute(gc, null, 
        							lsf , null,null,null,false,null,def,
        							new double[] {croppedMinValue},
        							new double[]{croppedMaxValue+1},
        							new int[] {(int) ((croppedMaxValue-croppedMinValue)+1)},
        							null,false);
        					
        					Statistics[] s = rezults.get(0).getStatsPerBandNoClassifierNoRange(0);
        					m.put("Min",(double)s[0].getResult());
        					m.put("Max",(double)s[1].getResult());
        					m.put("Mean",(double)s[2].getResult());
        					m.put("Median",(double)s[3].getResult());
        					double[] histArray = (double[])s[4].getResult();
        					TreeMap<String, Integer> hm = new TreeMap<String,Integer>(); 
        					for (int ii = 0;ii<histArray.length;ii++) {
        						hm.put('"' + Integer.toString((int)(croppedMinValue + ii)) + '"', (int)histArray[ii]);
        					}
        					m.put("Hist", hm.toString());//Arrays.toString((double[])s[4].getResult()));
        					
        				} catch (Exception e) {
        					// TODO Auto-generated catch block
        					e.printStackTrace();
        				}
                		gc.dispose(true);
            		}
                	curZone.setAttribute(coverageNames[i][0],m);
            	}//end for
            	
            }//end for
 	        SimpleFeatureCollection result = DataUtilities.collection(tmpList);
	        return result;
    	}

	/**
	 * @param zoneCoverageURL
	 * @throws IOException
	 */
	GridCoverage2D getCroppedCoverage(URL zoneCoverageURL) throws IOException {
		GeoTiffReader reader = null;
		GridCoverage2D gc = null;
		try {
			reader = new GeoTiffReader(zoneCoverageURL.openStream());
		} catch (IndexOutOfBoundsException e) {

		} catch (DataSourceException dse) {

		}

		if (reader != null && reader.getGridCoverageCount() > 0) {
			// get a grid coverage
			gc = (GridCoverage2D) reader.read(new GeneralParameterValue[0]);
			reader.dispose();
		}

		return gc;
	}
		/**
		 * @param covInfo
		 * @param zoneGeom
		 */
		boolean isWithinCoverage(Geometry zoneGeom, CoverageInfo covInfo) {
			
			boolean isWithin=false;
			
			try {
				ReferencedEnvelope re= ReferencedEnvelope.create(JTS.toEnvelope(zoneGeom.getEnvelope()),
						covInfo.getCRS());;
				
				isWithin= covInfo.boundingBox().contains(re.toBounds(covInfo.getCRS()));
			} catch (Exception e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
			return isWithin;
		}
		
		/**
		 * @param Geometry zoneGeom
		 * @param GridCoverage2D coverage
		 */
		boolean isWithinCoverage(Geometry zoneGeom, GridCoverage2D coverage) {
			
			boolean isWithin=false;
			
			try {
				ReferencedEnvelope re= ReferencedEnvelope.create(JTS.toEnvelope(zoneGeom.getEnvelope()),
						coverage.getCoordinateReferenceSystem());;
				
				isWithin= coverage.getEnvelope2D().contains(re.toBounds(coverage.getCoordinateReferenceSystem()));
			} catch (Exception e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
			return isWithin;
		}
		/**
		 * @param geometry
		 * @param inputCRS
		 * @param targetCRS TODO
		 * @return
		 */
		Geometry transformGeometry(Geometry geometry, 
				CoordinateReferenceSystem inputCRS, 
				CoordinateReferenceSystem targetCRS) {

			try {
				geometry =  JTS.transform(geometry,
						CRS.findMathTransform(inputCRS, targetCRS, true));
			} catch (MismatchedDimensionException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			} catch (TransformException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			} catch (FactoryException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
			return geometry;
		}
		/**
		 * @param coverageName
		 * @param fireOrigin
		 * @return
		 * @throws MalformedURLException
		 * @throws IOException
		 */
		private String getFeatureInfo(CoverageInfo coverageName, Point fireOrigin)
				throws MalformedURLException, IOException {
			/**
			 * This is a nifty trick--borrowed from
			 * https://gis.stackexchange.com/questions/58707/can-geoserver-return-the-raster-value-of-a-lat-lon-point
			 * 
			 */
			URL getFeatureInfo = new URL(GEOSERVER_URL +
					"/wms?SERVICE=WMS" + 
					"&VERSION=1.1.1" + 
					"&REQUEST=GetFeatureInfo" + 
					"&QUERY_LAYERS=" + coverageName.prefixedName() + 
					"&LAYERS=" + coverageName.prefixedName() + 
					"&INFO_FORMAT=text/plain" + 
					"&X=50" + 
					"&Y=50" + 
					"&SRS=" + coverageName.getCRS().getIdentifiers().toArray()[0] + 
					"&WIDTH=101" + 
					"&HEIGHT=101" + 
					"&BBOX=" +
					(fireOrigin.getX() - 0.1) + "," + (fireOrigin.getY() - 0.1) + "," + (fireOrigin.getX() + 0.1) + "," + (fireOrigin.getY() + 0.1));
			Object content = getFeatureInfo.openConnection().getInputStream().readAllBytes();
			String res = new String((byte [])content, StandardCharsets.UTF_8);
			
			try {
				res = res.split("=")[1].split("-")[0].trim();
			} catch (Exception e) {
				e.printStackTrace();
				LOGGER.fine("Something happened: " + res + fireOrigin.toText());
				res = null;
			}
			
			return res;
		}

	    @SuppressWarnings("unused")
		private void writeToFile(GridCoverage2D gc, String string) throws IllegalArgumentException, IOException {
	    	// TODO Auto-generated method stub
	    	File zoneFile = new File (string); 
	    	AbstractGridFormat format = (AbstractGridFormat) new GeoTiffFormat();        
	    	// writing it down
	    	GridCoverageWriter writer = format.getWriter(zoneFile);
	    	writer.write(gc, null);
	    	writer.dispose();

	    }
		private SimpleFeatureType buildFeatureTypeforStats (SimpleFeatureCollection s){
	    	SimpleFeatureType featureType = s.getSchema();
        	SimpleFeatureTypeBuilder tb = new SimpleFeatureTypeBuilder();
        	tb.setName("modified_zones");
        	tb.setCRS(featureType.getCoordinateReferenceSystem()); // not interested in warnings from this simple method
            tb.addAll(featureType.getAttributeDescriptors());
            tb.setDefaultGeometry(featureType.getGeometryDescriptor().getLocalName());
            for (int i=0;i<coverageNames.length;i++) {
            	tb.add(coverageNames[i][0],Map.class);
            }
            return tb.buildFeatureType();
	    }
}
