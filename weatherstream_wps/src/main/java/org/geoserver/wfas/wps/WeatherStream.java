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
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;

import javax.measure.Quantity;
import javax.measure.quantity.Length;
import javax.measure.quantity.Speed;
import javax.measure.quantity.Temperature;

import org.geoserver.catalog.Catalog;
import org.geoserver.catalog.CoverageInfo;
import org.geoserver.catalog.FeatureTypeInfo;
import org.geoserver.wps.process.ByteArrayRawData;
import org.geotools.coverage.grid.GridCoverage2D;
import org.geotools.coverage.grid.io.GridCoverage2DReader;
import org.geotools.coverage.grid.io.StructuredGridCoverage2DReader;
import org.geotools.factory.CommonFactoryFinder;
import org.geotools.feature.FeatureCollection;
import org.geotools.gce.imagemosaic.ImageMosaicFormat;
import org.geotools.geometry.DirectPosition2D;
import org.geotools.process.factory.DescribeParameter;
import org.geotools.process.factory.DescribeProcess;
import org.geotools.process.factory.DescribeResult;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Point;
import org.opengis.coverage.grid.GridCoverage;
import org.opengis.coverage.grid.GridCoverageReader;
import org.opengis.filter.Filter;
import org.opengis.filter.FilterFactory2;
import org.opengis.geometry.MismatchedDimensionException;
import org.opengis.parameter.GeneralParameterValue;
import org.opengis.parameter.ParameterValue;

import systems.uom.common.USCustomary;
import tec.uom.se.quantity.Quantities;
import tec.uom.se.unit.Units;

@DescribeProcess(title = "WeatherStream", description = "A Web Processing Service which generates Weather Stream  output for use in Flammap/Farsite")
public class WeatherStream extends WFASProcess {
	
	private DateFormat dFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss");
	protected Date lastDate;
	private Calendar cal = Calendar.getInstance();
	private static final Logger LOGGER = Logger.getLogger(WeatherStream.class.toString());
	private List<String> namespaces = Arrays.asList("rtma", "ndfd", "gfs");
	//private List<String> coveragesList = Arrays.asList("Temperature");//, "Relative_humidity", "Total_precipitation",
			//"Wind_speed", "Wind_direction", "Cloud_cover");
	
	public WeatherStream(Catalog catalog) {
		super(catalog);
		// TODO Auto-generated constructor stub
	}
	
	private String getTimeZoneId(Point p) {
		FeatureTypeInfo timezones = this.catalog.getFeatureTypeByName("osm", "timezones" );
		FeatureCollection tzcoll = null;
		try {
			FilterFactory2 ff = CommonFactoryFinder.getFilterFactory2( null );
			Filter filter = ff.contains(ff.property( "the_geom" ), ff.literal(p));
			tzcoll = timezones.getFeatureSource(null, null).getFeatures(filter);
		} catch (IOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		String tzid = tzcoll.features().next().getProperty("tzid").getValue().toString();
		return tzid;
	}
	
	/**
	 * Parses input string to UTC date.
	 * @param d Input date as a string
	 * @param tzid Time zone ID for the input lat/lon coordinates.
	 * @return UTC Date, or null if @param d is null or couldn't be parsed
	 */
	private Date parseDatetoUTC(String d, String tzid) {
		Date parsedDate = null;
		DateFormat df;
		List <String> dateFormats = Arrays.asList("yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd");
		for (String dateFormat : dateFormats)
		{
			try {
				df = new SimpleDateFormat(dateFormat);
				df.setTimeZone(TimeZone.getTimeZone(tzid));
				parsedDate = df.parse(d);
				break;
			} catch (ParseException e) {
				LOGGER.fine(d  + " could not be parsed to date, returning null...");
			}catch (NullPointerException e) {
				LOGGER.fine("Date is probably not specified, returning null...");
			}

		}
		return parsedDate;
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
			@DescribeParameter(name = "English units", description = "English units if true, metric units if false", 
								min = 0, defaultValue = "true") Boolean useEnglishUnits,
			@DescribeParameter(name = "Archive", 
								description = "Name of the archive from which the WeatherStream file will be "
										+ "generated: rtma, ndfd, or gfs. Default is all three.", 
								min = 0, defaultValue = "all") String archive,
			@DescribeParameter(name = "Start date", description = "Starting date for which weather data should be extracted. Default is archive's first date.", 
								min = 0) String startDateStr,
			@DescribeParameter(name = "End date", description = "End date for which weather data should be extracted. Default is archive's last date.", 
								min = 0) String endDateStr)
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
		
		transPoint = transformPoint(input, dem.getCRS());
		Number height = (Number) Array.get(dc.evaluate(new DirectPosition2D(transPoint.getX(),
				transPoint.getY())),0);
		dgc.dispose();
		dc = null;
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
			return new ByteArrayRawData(out.toByteArray(), "text/csv", "csv");
		}
		/*
		 * Extract time zone id for this point: 
		 */
		String tzid = getTimeZoneId(input);
		cal.setTimeZone(TimeZone.getTimeZone(tzid));
		Date startDate = parseDatetoUTC(startDateStr,tzid);
		Date endDate = parseDatetoUTC(endDateStr,tzid);
		
		/*
		 * Write elevation results, 
		 * and the units used (metric or English):
		 */
		if (useEnglishUnits) {
			Quantity <Length> qt = Quantities.getQuantity(height.intValue(), Units.METRE)
					.to(USCustomary.FOOT);
			csvWriter.append("RAWS_ELEVATION: " + qt.getValue().intValue()  + "\n" + "RAWS_WINDS: Ave\n" + "RAWS_UNITS: English\n\n");// sample			
		} else {
			csvWriter.append("RAWS_ELEVATION: " + height.intValue()  + "\n" + "RAWS_WINDS: Ave\n" + "RAWS_UNITS: Metric\n\n");
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
				 * check for overlap with a previous dataset:
				 */
				if (lastDate!=null && !timeD.after(lastDate) ) {
					continue;
				}
				
				if (startDate!=null && timeD.before(startDate) ){
					continue;
				}
				
				if (endDate!=null && timeD.after(endDate) ){
					break;
				}
				WeatherRecord wr = new WeatherRecord(); 
				wr.date = timeD;
				cal.setTime(timeD);
				time.setValue(new ArrayList() { { add(timeD); } }); 
				final GeneralParameterValue[] values = new GeneralParameterValue[] { time }; 
				
				ExecutorService WORKER_THREAD_POOL 
				  = Executors.newFixedThreadPool(ciList.size());
				
				for (CoverageInfo ci : ciList) { 
					WORKER_THREAD_POOL.execute(new Runnable(){
						@Override
						public void run(){//start a thread for each coverage for this time step
							// transform the input point coords to coverage CRS:
							transPoint = transformPoint(input,ci.getCRS());
							StructuredGridCoverage2DReader reader = getCoverageReader(ci);
							GridCoverage2D gc = null;
							try {
								gc = reader.read(values);
							} catch (IOException e) {
								// TODO Auto-generated catch block
								e.printStackTrace();
							}

							Number val = (Number) Array.get(gc.evaluate(new DirectPosition2D(transPoint.getX(),
									transPoint.getY())),0); 
							UnitFormatter.format(ci, val, useEnglishUnits, wr);
							gc.dispose(true);					
						}//end run
					});//end execute
				} //end for Coverage
				WORKER_THREAD_POOL.shutdown();
				try {
					WORKER_THREAD_POOL.awaitTermination(1, TimeUnit.MINUTES);
					//System.gc();
				} catch (InterruptedException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}

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
			}//end for	date
			String lastTimeStep = tList.get(tList.size()-1);
			lastDate = dFormat.parse(lastTimeStep.substring(0, lastTimeStep.length()-1));
			lastTimeStep=null;
			tList=null;
			ciList=null;
			timestamps=null;
		}//end for
		
		csvWriter.flush();
		csvWriter.close();
		System.gc();
		return new ByteArrayRawData(out.toByteArray(), "text/csv", "wxs");
	}//end execute	
}//end class

/**
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

/**
 * @author Alexander Petkov
 * A Class to format and transform
 * coverage results to scientific units 
 */
class UnitFormatter{
	static void format(CoverageInfo ci, Number val, Boolean useEnglishUnits, WeatherRecord wr) {
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
			wr.tmp = tmpQt.getValue().intValue();
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
		}//end switch	
	}//end format 	
}//end class
