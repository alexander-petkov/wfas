package org.geoserver.wfas.wps;

import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.media.jai.Interpolation;

import org.geoserver.wps.gs.GeoServerProcess;
import org.geotools.coverage.grid.GridCoverage2D;
import org.geotools.coverage.grid.GridEnvelope2D;
import org.geotools.coverage.grid.GridGeometry2D;
import org.geotools.coverage.grid.io.imageio.GeoToolsWriteParams;
import org.geotools.coverage.processing.CoverageProcessor;
import org.geotools.gce.geotiff.GeoTiffWriteParams;
import org.geotools.geometry.GeneralEnvelope;
import org.geotools.geometry.jts.JTS;
import org.geotools.geometry.jts.JTSFactoryFinder;
import org.geotools.geometry.jts.ReferencedEnvelope;
import org.geotools.process.factory.DescribeParameter;
import org.geotools.process.factory.DescribeProcess;
import org.geotools.process.factory.DescribeResult;
import org.geotools.referencing.CRS;
import org.geotools.util.Utilities;
import org.geotools.util.factory.Hints;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.GeometryCollection;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.opengis.coverage.grid.GridGeometry;
import org.opengis.coverage.processing.Operation;
import org.opengis.geometry.Envelope;
import org.opengis.geometry.MismatchedDimensionException;
import org.opengis.parameter.ParameterValueGroup;
import org.opengis.referencing.FactoryException;
import org.opengis.referencing.crs.CoordinateReferenceSystem;
import org.opengis.referencing.operation.MathTransform;
import org.opengis.referencing.operation.TransformException;

import it.geosolutions.jaiext.range.RangeFactory;
@DescribeProcess(title = "Landscape export", description = "A Web Processing Service which exports an 8-band Lanscape Geotiff suitable for use in Flammap/Farsite")
public class LandscapeExportWPS implements GeoServerProcess {
	private final static GeoTiffWriteParams DEFAULT_WRITE_PARAMS;

    static {
        // setting the write parameters (we my want to make these configurable in the future
        DEFAULT_WRITE_PARAMS = new GeoTiffWriteParams();
        DEFAULT_WRITE_PARAMS.setCompressionMode(GeoTiffWriteParams.MODE_EXPLICIT);
        DEFAULT_WRITE_PARAMS.setCompressionType("LZW");
        DEFAULT_WRITE_PARAMS.setCompressionQuality(0.75F);
        DEFAULT_WRITE_PARAMS.setTilingMode(GeoToolsWriteParams.MODE_EXPLICIT);
        DEFAULT_WRITE_PARAMS.setTiling(512, 512);
    }
	private static final CoverageProcessor PROCESSOR = CoverageProcessor.getInstance();
	private static final Logger LOGGER = Logger.getLogger(LandscapeExportWPS.class.toString());
	private String wkt;
	private MathTransform transform;
	private Point input;
	private Point transPoint;
	private CoordinateReferenceSystem crs;
	private GeometryFactory geometryFactory = JTSFactoryFinder.getGeometryFactory();

	/**
	 * @return Gridcoverage2d A subset of a Landscape file.
	 */
	@DescribeResult(name = "output", description = "8-band Landscape Geotiff", type = GridCoverage2D.class)
	public GridCoverage2D execute(
			@DescribeParameter(name = "Longitude", description = "Center Longitude for Landscape file") Double lon,
			@DescribeParameter(name = "Latitude", description = "Center latitude for Landscape file") Double lat,
			@DescribeParameter(name = "coverage", description = "Input raster") GridCoverage2D coverage,
			@DescribeParameter(name = "Scale Factor", description = "Output resolution: minimum value 0.1 (10 times coarser resolution), maximum=1 (original resolution)", defaultValue="1", min=0, minValue=0.1, maxValue=1.0) double scaleFactor,
			@DescribeParameter(name = "Extent", description = "Extent of the output files (in miles): minimum 5, maximum 60.", defaultValue="5", min=1, minValue=5, maxValue=60) Integer extent) 
			throws IOException, MismatchedDimensionException {
		/*
		 * Check inputs for
		 * out of range values:
		 */
		if (scaleFactor < 0.1) {
			if (LOGGER.isLoggable(Level.FINE)) {
				LOGGER.fine("Specified scale factor less than 0.1, setting to 0.1.");
				scaleFactor = 0.1;
			}
		} else if (scaleFactor > 1) {
				if (LOGGER.isLoggable(Level.FINE)) {
					LOGGER.fine("Specified scale factor is more than 1, setting to 1.");
					scaleFactor = 1.0;
				}
		}//end if
		
		if (extent < 5) {
			if (LOGGER.isLoggable(Level.FINE)) {
				LOGGER.fine("Extent less than 5 miles, setting to 5.");
				extent = 5;
			}
		} else if (extent > 60) {
			if (LOGGER.isLoggable(Level.FINE)) {
				LOGGER.fine("Extent more than 60 miles, setting to 60.");
				extent = 60;
			}
		}//end if
				
		/*
		 * construct a point geometry for which we should query weather data:
		 */
		input = geometryFactory.createPoint(new Coordinate(lon, lat));
		input.setSRID(4326);

		wkt = buildCustomAlbersWkt(lon, lat, extent);

		try {
			crs = CRS.parseWKT(wkt);
			transform = CRS.findMathTransform(CRS.decode("EPSG:" + input.getSRID()), crs);
			transPoint = (Point) JTS.transform(input, transform);
		} catch (Exception e) {
			if (LOGGER.isLoggable(Level.FINE)) {
				LOGGER.fine("Unable to parse Albers projection from input coords: " + e.toString());
			} // end if
		} // end catch
		
		/*
		 * 1 mile has 1609.34 meters
		 */
		ReferencedEnvelope envelope = new ReferencedEnvelope((extent / 2) * 1609.34 * (-1), // min x
				(extent / 2) * 1609.34, // max x
				(extent / 2) * 1609.34 * (-1), // min y
				(extent / 2) * 1609.34, // max x,
				crs);

		/*
		 * @TODO Check that input point is within CONUS extent and that we can get elev data
		 * for it:
		 */

		/*
		 * Transform our custom Albers-generated envelope to coverage CRS envelope:
		 */
		ReferencedEnvelope coverageEnv = new ReferencedEnvelope();
		try {
			coverageEnv = envelope.transform(coverage.getCoordinateReferenceSystem(), true);
		} catch (TransformException e1) {
			// TODO Auto-generated catch block
			e1.printStackTrace();
		} catch (FactoryException e1) {
			// TODO Auto-generated catch block
			e1.printStackTrace();
		}
		/**
		 * Expand this envelope, so after reprojection, 
		 * rotation and cropping, the result won't have
		 * large nodata areas.
		 */
		coverageEnv.expandBy(coverageEnv.getWidth()/2,coverageEnv.getHeight()/2);
		GeneralEnvelope bounds = new GeneralEnvelope(coverageEnv);
		GeometryCollection roi = geometryFactory
				.createGeometryCollection(new Geometry[] { JTS.toGeometry(coverageEnv) });

		// perform the crops
		ParameterValueGroup param = PROCESSOR.getOperation("CoverageCrop").getParameters();
		param.parameter("Source").setValue(coverage);
		param.parameter("Envelope").setValue(bounds);
		param.parameter("ROI").setValue(roi);
		param.parameter("NoData").setValue(RangeFactory.create(-9999, -9999));
		param.parameter("destNoData").setValue(new double[] {-9999});
		GridCoverage2D result =  (GridCoverage2D) PROCESSOR.doOperation(param);
		
		coverage.dispose(true);
		
		/*
		 * Should we rescale?:
		 */
		if (scaleFactor<1) {
			
			result = handleRescaling(result,
					Interpolation.getInstance(Interpolation.INTERP_NEAREST), scaleFactor);
		}
		
		//reproject to custom CRS
		result = handleReprojection(result, crs,
				Interpolation.getInstance(Interpolation.INTERP_NEAREST), null);

		//final crop
		param = PROCESSOR.getOperation("CoverageCrop").getParameters();
		param.parameter("Source").setValue(result);
		param.parameter("Envelope").setValue(envelope);

		result =  (GridCoverage2D) PROCESSOR.doOperation(param);
		
		return result;
	}

	/**
	 * Calculate the length for 1 degree longitude at input latitude
	 * @param lon
	 * @param lat
	 * @return miles the length for 1 degree longitude
	 */
	private double calcOneDegreeLonLength (Double lon, Double lat) {
		/** 
		 * convert Input Latitude from dec degrees to radians:
		 */
		double rad = Math.toRadians(lat);
		/**
		 * Calculate cosine:
		 */
		double cos = Math.cos(rad);
		/**
		 * Calculate length of 1 degree longitude at input lat
		 * in miles( 69.172 is the length in miles for 
		 * 1 deg longitude at the equator):
		 */
		double miles = cos * 69.172;

		return miles;
	}
	
	/**
	 * Parse a custom Albers Equal Area WKT definition with custom parallels.
	 * 
	 * @param lon
	 * @param lat
	 * @return custom Albers WKT centered at input coords, and with standard
	 *         parallels 60 miles apart from each other.
	 */
	private String buildCustomAlbersWkt(Double lon, Double lat, Integer extent) {

		/*
		 * One degree latitude is approx 69 miles. We are looking for 60 miles extent,
		 * so set the standard parallels 60 miles apart (60/69)/2=0.434 degrees latitude
		 * in each direction.
		 */
		String wkt = "PROJCS[\"Custom_Albers_Conic_Equal_Area\",\n" + "  GEOGCS[\"GCS_North_American_1983\",\n"
				+ "    DATUM[\"D_North_American_1983\",\n" + "    SPHEROID[\"GRS_1980\",6378137.0,298.257222101]],\n"
				+ "    PRIMEM[\"Greenwich\",0.0],\n" + "    UNIT[\"Degree\",0.0174532925199433]],\n"
				+ "  PROJECTION[\"Albers_Conic_Equal_Area\", AUTHORITY[\"EPSG\",\"9822\"]],\n"
				+ "  PARAMETER[\"False_Easting\",0.0],\n" + "  PARAMETER[\"False_Northing\",0.0],\n"
				+ "  PARAMETER[\"Central_Meridian\"," + lon.toString() + "],\n" 
				+ "  PARAMETER[\"Standard_Parallel_1\"," + ((Double) (lat - 0.434)).toString() + "],\n" 
				+ "  PARAMETER[\"Standard_Parallel_2\"," + ((Double) (lat + 0.434)).toString() + "],\n" 
				+ "  PARAMETER[\"Latitude_Of_Origin\"," + lat.toString() + "],\n" 
				+ "  UNIT[\"Meter\",1.0]]";
		return wkt;
	}

	private GridCoverage2D handleReprojection(GridCoverage2D coverage, CoordinateReferenceSystem targetCRS,
			Interpolation spatialInterpolation, Hints hints) {
		// checks
		Utilities.ensureNonNull("interpolation", spatialInterpolation);
		// check the two crs to see if we really need to do anything
		if (CRS.equalsIgnoreMetadata(coverage.getCoordinateReferenceSystem2D(), targetCRS)) {
			return coverage;
		}

		// reproject
		final CoverageProcessor processor = hints == null ? CoverageProcessor.getInstance()
				: CoverageProcessor.getInstance(hints);
		final Operation operation = processor.getOperation("Resample");
		final ParameterValueGroup parameters = operation.getParameters();
		
		parameters.parameter("Source").setValue(coverage);
		parameters.parameter("CoordinateReferenceSystem").setValue(targetCRS);
		parameters.parameter("InterpolationType").setValue(spatialInterpolation);

		return (GridCoverage2D) processor.doOperation(parameters);
	}
	
	/*
	 * This method handles the scaling of a coverage, 
	 * using "Resample" operation.
	 * This is similar to the handleReprojection method, 
	 * except resampled to a coarser GridGeometry.
	 * The "Scale" Operation method wouldn't preserve NoData areas, 
	 * hence utilizing "Resample" again. 
	 */
	private GridCoverage2D handleRescaling(GridCoverage2D coverage,
			Interpolation spatialInterpolation, double scaleFactor) {
		// checks
		Utilities.ensureNonNull("interpolation", spatialInterpolation);
		
		//resample
		final CoverageProcessor processor = CoverageProcessor.getInstance();
		final Operation operation = processor.getOperation("Resample");
		final ParameterValueGroup parameters = operation.getParameters();
		
		parameters.parameter("Source").setValue(coverage);
		parameters.parameter("InterpolationType").setValue(spatialInterpolation);
		
		/*
		 * Should we rescale?:
		 */
		if (scaleFactor<1) {
			GridGeometry2D curGridGeom = coverage.getGridGeometry();
			Envelope curEnv = curGridGeom.getEnvelope2D();

			GridEnvelope2D curGridEnv = curGridGeom.getGridRange2D();
			// create new GridGeometry with current size*scaleFactor as many cells
			GridEnvelope2D newGridEnv = new GridEnvelope2D(
					curGridEnv.x, curGridEnv.y, ((int)(curGridEnv.width * scaleFactor)),
					((int)(curGridEnv.height * scaleFactor)));
			GridGeometry newGridGeom = new GridGeometry2D(newGridEnv, curEnv);
			parameters.parameter("GridGeometry").setValue(newGridGeom);
		}else {
			parameters.parameter("GridGeometry").setValue(null);
		}
		return (GridCoverage2D) processor.doOperation(parameters);
	}
}
