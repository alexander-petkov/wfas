package org.geoserver.wfas.wps;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintWriter;
import java.lang.reflect.Array;
import java.text.DateFormat;
import java.text.DecimalFormat;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.List;

import javax.measure.Quantity;
import javax.measure.quantity.Length;
import javax.measure.quantity.Speed;
import javax.measure.quantity.Temperature;

import org.geoserver.catalog.Catalog;
import org.geoserver.catalog.CoverageInfo;
import org.geoserver.wps.gs.GeoServerProcess;
import org.geoserver.wps.process.ByteArrayRawData;
import org.geotools.coverage.grid.GridCoverage2D;
import org.geotools.coverage.grid.io.GridCoverage2DReader;
import org.geotools.coverage.grid.io.StructuredGridCoverage2DReader;
import org.geotools.gce.imagemosaic.ImageMosaicFormat;
import org.geotools.geometry.DirectPosition2D;
import org.geotools.geometry.jts.JTS;
import org.geotools.geometry.jts.JTSFactoryFinder;
import org.geotools.process.factory.DescribeParameter;
import org.geotools.process.factory.DescribeProcess;
import org.geotools.process.factory.DescribeResult;
import org.geotools.referencing.CRS;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.opengis.coverage.grid.GridCoverage;
import org.opengis.coverage.grid.GridCoverageReader;
import org.opengis.geometry.MismatchedDimensionException;
import org.opengis.parameter.GeneralParameterValue;
import org.opengis.parameter.ParameterValue;
import org.opengis.referencing.operation.MathTransform;

import systems.uom.common.USCustomary;
import tec.uom.se.quantity.Quantities;
import tec.uom.se.unit.Units;

@DescribeProcess(title = "WeatherStreamWPS", description = "A Web Processing Service which generates Weather Stream  output for use in Flammap/Farsite")
public class WeatherStreamWPS implements GeoServerProcess {
	private Catalog catalog;
	private StructuredGridCoverage2DReader reader = null;
	private MathTransform transform;
	private Point input;
	private Point transPoint;
	private DateFormat dFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss");
	private Date lastDate;
	private Calendar cal = Calendar.getInstance();
	private static String LANDFIRE_NAMESPACE = "landfire";
	private static String LANDFIRE_DEM = "us_dem_2016";	
	
	private List<String> namespaces = Arrays.asList("rtma", "ndfd", "gfs");
	//private List<String> coveragesList = Arrays.asList("Temperature");//, "Relative_humidity", "Total_precipitation",
			//"Wind_speed", "Wind_direction", "Cloud_cover");

	/* GeometryFactory will be used to create 
	 * the Point geometry for which we should query
	 */
	GeometryFactory geometryFactory = JTSFactoryFinder.getGeometryFactory();
	
	/*
	 * The overlapping extent for all 3 datasets
	 */
	Geometry envelope= null;
	

	public WeatherStreamWPS(Catalog catalog) {
		this.catalog = catalog;
	}

	/**
	 * @param lon
	 * @param lat
	 * @param useEnglishUnits
	 * @return
	 * @throws IOException
	 * @throws MismatchedDimensionException
	 * @throws ParseException
	 */
	@DescribeResult(name = "output", description = "Weather stream output", meta = { "mimeTypes=text/csv",
			"chosenMimeType=text/csv" })
	public ByteArrayRawData execute(
			@DescribeParameter(name = "Longitude", description = "Longitude for which to extract weather info") Double lon,
			@DescribeParameter(name = "Latitude", description = "Latitude for which to extract weather info") Double lat,
			@DescribeParameter(name = "English units", description = "English units if true, metric units if false", defaultValue = "true") Boolean useEnglishUnits,
			@DescribeParameter(name = "Archive", 
								description = "Name of the archive from which the WeatherStream file will be "
										+ "generated: rtma, ndfd, or gfs. Default is all three.", 
								defaultValue = "all") String archive)
					throws IOException, MismatchedDimensionException, ParseException {
		/*
		 * Initialize to null at the beginning of each run:
		 */
		lastDate=null;
		
		/*
		 * Determine which archive to query:
		 */
		switch (archive) {
			case "rtma":
				namespaces = Arrays.asList("rtma");
				break;
			case "ndfd":
				namespaces = Arrays.asList("ndfd");
				break;
			case "gfs":
				namespaces = Arrays.asList("gfs");
				break;
			default:
				namespaces = Arrays.asList("rtma", "ndfd", "gfs");
		}
		/*
		 * Open an output stream to which to write:
		 */
		ByteArrayOutputStream out = new ByteArrayOutputStream();
		PrintWriter csvWriter = new PrintWriter(out);
		
		
		/*
		 *  construct a point geometry for which we should query weather data:
		 */
		input = geometryFactory.createPoint(new Coordinate(lon, lat));
		input.setSRID(4326);

		/*
		 * Check that input point is within CONUS extent 
		 * and that we can get elev data for it:
		 */
		
		CoverageInfo dem = catalog.getCoverageByName(LANDFIRE_NAMESPACE, LANDFIRE_DEM);
		
		GridCoverageReader dgc = dem.getGridCoverageReader(null, null);
		GridCoverage dc = dgc.read(null);
		
		/*
		 * @TODO: extract Coordinate transformation
		 * code to a method. 
		 */
		try { 
			transform =
						CRS.findMathTransform(CRS.decode("EPSG:" + input.getSRID()), dem.getCRS());
				transPoint = (Point) JTS.transform(input, transform);
				transPoint.setSRID(Integer.parseInt(CRS.toSRS(dem.getCRS(),true)));
		} catch (Exception e) { 
			//TODO Auto-generated catch block e.printStackTrace(csvWriter); }
		}
		Number height = (Number) Array.get(dc.evaluate(new DirectPosition2D(transPoint.getX(),
				transPoint.getY())),0);
		
		if (useEnglishUnits) {
			Quantity <Length> qt = Quantities.getQuantity(height.intValue(), Units.METRE)
					.to(USCustomary.FOOT);
			csvWriter.append("RAWS_ELEVATION: " + qt.getValue().intValue()  + "\n" + "RAWS_WINDS: Ave\n" + "RAWS_UNITS: English\n\n");// sample			
		} else {
			csvWriter.append("RAWS_ELEVATION: " + height.intValue()  + "\n" + "RAWS_WINDS: Ave\n" + "RAWS_UNITS: Metric\n\n");
		}


		/*
		 * quit if out of bounds, or NaN 
		 * elevation value for requested coordinates
		 * @TODO: Extract to  quit() method to reduce 
		 * code duplication.
		 */
		if (height.intValue() <0 ) {
			csvWriter.append("Input coordinates are out of CONUS area, ending process...\n");
			csvWriter.flush();
			csvWriter.close();
			dgc.dispose();
			return new ByteArrayRawData(out.toByteArray(), "text/csv", "csv");
		}

		// sample headings, are they needed or optional?
		csvWriter.append("Year  Mth  Day   Time    Temp     RH    HrlyPcp   WindSpd  WindDir CloudCov\n");

		for (String ns : namespaces) {
			List<CoverageInfo> ciList = catalog.getCoveragesByNamespace(catalog.getNamespaceByPrefix(ns));
			
			String timestamps = ciList.get(0)
					.getGridCoverageReader(null, null)
					.getMetadataValue(GridCoverage2DReader.TIME_DOMAIN);
			List <String> tList= Arrays.asList(timestamps.split(","));
			
			Collections.sort(tList);
			
			final ParameterValue<List> time = ImageMosaicFormat.TIME.createValue(); 
			
			for (String tStep:tList) {
				Date timeD = dFormat.parse(tStep.substring(0,tStep.length()-1));
				
				/**
				 * check whether we should continue on from 
				 * another dataset:
				 */
				if (lastDate!=null && !timeD.after(lastDate) ) {
						continue;
					}
				
				WeatherRecord wr = new WeatherRecord(); 
				wr.date = timeD;
				cal.setTime(timeD);
				time.setValue(new ArrayList() { { add(timeD); } }); 
				GeneralParameterValue[] values = new GeneralParameterValue[] { time }; 
					
			for (CoverageInfo ci : ciList) { 
				//CoverageInfo ci = ciList.fstream().filter(cInfo->cname.equals(cInfo.getName())).findFirst();//catalog.getCoverageByName(ns, cname); 
				// transform the input point coords to coverage CRS:
				
				try { 
					transform =
								CRS.findMathTransform(CRS.decode("EPSG:" + input.getSRID()), ci.getCRS());
						transPoint = (Point) JTS.transform(input, transform); 
						transPoint.setSRID(Integer.parseInt(CRS.toSRS(ci.getCRS(),true)));
				} catch (Exception e) { 
					//TODO Auto-generated catch block e.printStackTrace(csvWriter); }
				}

				GridCoverageReader genericReader = ci.getGridCoverageReader(null, null); 
				// we have a descriptor, now we need to find the association between the exposed 
				//dimension names and the granule source attributes
				 
				try { 
					reader = (StructuredGridCoverage2DReader) genericReader; 
				} catch (ClassCastException e) { 
					// TODO Auto-generated catch block break; }
				}
				//final ParameterValue<List> time = ImageMosaicFormat.TIME.createValue();
//				String timestamps = reader.getMetadataValue(GridCoverage2DReader.TIME_DOMAIN);
//				List <String> tList= Arrays.asList(timestamps.split(","));
//				
//				Collections.sort(tList);
//				//csvWriter.append(String.join( "; " , ci.getName(), reader.getMetadataValue(GridCoverage2DReader.TIME_DOMAIN), "\n"));
//				String coverageName = ci.getNativeCoverageName(); 
//				
//				if (coverageName == null) {
//					coverageName = reader.getGridCoverageNames()[0]; 
//				} 
//				
//				GranuleSource granules =
//										reader.getGranules(coverageName, true); 
//				// set up sorting by timestamp: 
//				Query q = new Query(granules.getSchema().getTypeName());
//				final SortBy[] granuleSort = new SortBy[] {
//						new SortByImpl(FeatureUtilities.DEFAULT_FILTER_FACTORY.property("time"), SortOrder.ASCENDING) };
//				q.setSortBy(granuleSort); 
//				SimpleFeatureCollection fc = granules.getGranules(q); 
//				SimpleFeatureIterator iterator = fc.features();


						GridCoverage2D gc = reader.read(values);
															
						Number val = (Number) Array.get(gc.evaluate(new DirectPosition2D(transPoint.getX(),
																	transPoint.getY())),0); 
						switch (ci.getName()) {
						case "Temperature":
							Quantity<Temperature> tmpQt;
							if (useEnglishUnits) {
								tmpQt = Quantities.getQuantity(val.floatValue(), Units.KELVIN)
										.to(USCustomary.FAHRENHEIT);
								
							} else {//convert to Celsius
								tmpQt = Quantities.getQuantity(val.floatValue(), Units.KELVIN)
										.to(Units.CELSIUS);
							}
							wr.tmp = tmpQt.getValue().floatValue();
							tmpQt = null;
							break;
						case "Relative_humidity":
							wr.rh = val.floatValue();
							break;
						case "Total_precipitation":
							/*
							 * all datasets provide precip in kg/m2 units which is the same as mm per time
							 * period
							 */
							Quantity<Length> l;
							if (useEnglishUnits) {
								l =  Quantities.getQuantity(val.floatValue()/1000,Units.METRE)
										.to(USCustomary.INCH);
								wr.tp =l.getValue().floatValue();
							} else {
								wr.tp = val.floatValue();
							}
							break;
						case "Wind_speed":
							Quantity<Speed> ws;
							if (useEnglishUnits) {
								ws= Quantities.getQuantity(val, Units.METRE_PER_SECOND)
										.to(USCustomary.MILE_PER_HOUR);
							} else {
								ws= Quantities.getQuantity(val, Units.METRE_PER_SECOND)
										.to(Units.KILOMETRE_PER_HOUR);
							}
							wr.ws = ws.getValue().floatValue();
							break;
						case "Wind_direction":
							wr.wd = val.floatValue();
							break;
						case "Cloud_cover":
							wr.cc = val.floatValue();
							break;
						}
						gc.dispose(false); 	
					} //end for Coverage
//				} finally {
//					iterator.close(); 
//			    }cal.get(Calendar.MONTH)
				csvWriter.append( (cal.get(Calendar.YEAR)) 
						+ String.format("%1$5s", cal.get(Calendar.MONTH)+1)
						+ String.format("%1$5s", cal.get(Calendar.DATE))
						+ String.format("%1$5s",String.format("%02d",cal.get(Calendar.HOUR_OF_DAY)))
						+ String.format("%02d",cal.get(Calendar.MINUTE))
						+ String.format("%1$8s", new DecimalFormat("#").format(wr.tmp))
						+ String.format("%1$7s", new DecimalFormat("#").format(wr.rh))
						+ String.format("%1$11s", new DecimalFormat("0.00").format(wr.tp))
						+ String.format("%1$9s", new DecimalFormat("#").format(wr.ws))
						+ String.format("%1$9s", new DecimalFormat("#").format(wr.wd))
						+ String.format("%1$6s", new DecimalFormat("#").format(wr.cc)) + "\n");
				//csvWriter.append("\n");
			}//end for	date
			String lastTimeStep = tList.get(tList.size()-1);
			lastDate = dFormat.parse(lastTimeStep.substring(0, lastTimeStep.length()-1));
			lastTimeStep=null;
		}//end for

		/*
		 * CoverageInfo ci = catalog.getCoverageByName("cite","Relative_humidity"); if
		 * (ci == null) { throw new WPSException("Could not find coverage..."); }
		 * 
		 * ImageMosaicReader reader = new ImageMosaicReader(ci.getStore().getURL(),
		 * null); final ParameterValueGroup readParametersDescriptor =
		 * reader.getFormat().getReadParameters(); final
		 * List<GeneralParameterDescriptor> parameterDescriptors =
		 * readParametersDescriptor.getDescriptor().descriptors();
		 * 
		 * List<CoverageDimensionInfo> dims = ci.getDimensions(); for
		 * (CoverageDimensionInfo param : dims) { csvWriter.append(String.join(",",
		 * param.getName(), param.getDescription()));
		 * 
		 * csvWriter.append("\n"); }
		 */
		csvWriter.flush();
		csvWriter.close();

		return new ByteArrayRawData(out.toByteArray(), "text/csv", "csv");
	}
	
//	/*
//	 * Check whether the input point is 
//	 * within the overlapping extent 
//	 * for the 3 datasets (rtma, ndfd and gfs)
//	 */
//	private boolean  checkWithin (Point input) {
//		boolean isWithin;
//		return isWithin;
//	}
}//end class
/*
 * @author Alexander Petkov
 * A Class structure to hold 
 * Flammamp Wxs weather data
 */
class WeatherRecord{
	  Date  date = null;
	  float tmp;
	  float rh;
	  float tp;
	  float wd;
	  float ws;
	  float cc; 
 }