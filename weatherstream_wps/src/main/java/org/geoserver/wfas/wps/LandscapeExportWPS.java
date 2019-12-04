package org.geoserver.wfas.wps;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.media.jai.Interpolation;

import org.geoserver.catalog.CoverageDimensionCustomizerReader.GridCoverageWrapper;
import org.geoserver.wcs2_0.WCSEnvelope;
import org.geoserver.wcs2_0.exception.WCS20Exception;
import org.geoserver.wps.gs.GeoServerProcess;
import org.geotools.coverage.grid.GridCoverage2D;
import org.geotools.coverage.processing.CoverageProcessor;
import org.geotools.geometry.Envelope2D;
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
import org.opengis.coverage.grid.GridCoverage;
import org.opengis.coverage.processing.Operation;
import org.opengis.geometry.Envelope;
import org.opengis.geometry.MismatchedDimensionException;
import org.opengis.parameter.ParameterValueGroup;
import org.opengis.referencing.FactoryException;
import org.opengis.referencing.crs.CoordinateReferenceSystem;
import org.opengis.referencing.operation.MathTransform;
import org.opengis.referencing.operation.TransformException;
import org.vfny.geoserver.util.WCSUtils;

@DescribeProcess(title = "Landscape export", description = "A Web Processing Service which exports an 8-band Lanscape Geotiff suitable for use in Flammap/Farsite")
public class LandscapeExportWPS implements GeoServerProcess {
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
			@DescribeParameter(name = "coverage", description = "Input raster") GridCoverage2D coverage)
			throws IOException, MismatchedDimensionException {
		/*
		 * construct a point geometry for which we should query weather data:
		 */
		input = geometryFactory.createPoint(new Coordinate(lon, lat));
		input.setSRID(4326);

		wkt = buildCustomAlbersWkt(lon, lat);

		try {
			crs = CRS.parseWKT(wkt);
			transform = CRS.findMathTransform(CRS.decode("EPSG:" + input.getSRID()), crs);
			transPoint = (Point) JTS.transform(input, transform);
		} catch (Exception e) {
			if (LOGGER.isLoggable(Level.FINE)) {
				LOGGER.fine("Unable to parse Albers projection from input coords: " + e.toString());
			} // end if
		} // end catch

		ReferencedEnvelope envelope = new ReferencedEnvelope(-48280.3, 48280.3, -48280.3, 48280.3, crs);

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
		GeneralEnvelope bounds = new GeneralEnvelope(coverageEnv);
		GeometryCollection roi = geometryFactory
				.createGeometryCollection(new Geometry[] { JTS.toGeometry(coverageEnv) });

		// perform the crops
		final ParameterValueGroup param = PROCESSOR.getOperation("CoverageCrop").getParameters();
		param.parameter("Source").setValue(coverage);
		param.parameter("Envelope").setValue(bounds);
		param.parameter("ROI").setValue(roi);

		GridCoverage2D result = handleReprojection((GridCoverage2D) PROCESSOR.doOperation(param), crs,
				Interpolation.getInstance(Interpolation.INTERP_NEAREST), null);

		return result;// geometryFactory.toGeometry(targetEnv);
	}

	/**
	 * @param lon
	 * @param lat
	 * @return custom Albers WKT centered at input coords, and with standard
	 *         parallels 60 miles apart from each other.
	 */
	private String buildCustomAlbersWkt(Double lon, Double lat) {
//		/** 
//		 * convert Input Latitude from dec degrees to radians:
//		 */
//		double rad = Math.toRadians(lat);
//		/**
//		 * Calculate cosine:
//		 */
//		double cos = Math.cos(rad);
//		/**
//		 * Calculate length of 1 degree longitude at input lat
//		 * in miles( 69.172 is the length in miles for 
//		 * 1 deg longitude at the equator):
//		 */
//		double miles = cos * 69.172;
//		/**
//		 * We aim for 60 miles extent, 
//		 * therefore calculate how many degrees longitude we should pad:
//		 */
//		double fraction = 60/miles;

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
		// check the two crs tosee if we really need to do anything
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
		parameters.parameter("GridGeometry").setValue(null);
		parameters.parameter("InterpolationType").setValue(spatialInterpolation);
		return (GridCoverage2D) processor.doOperation(parameters);
	}

	/**
	 * This method is responsible for cropping the provided {@link GridCoverage}
	 * using the provided subset envelope.
	 *
	 * <p>
	 * The subset envelope at this stage should be in the native crs.
	 *
	 * @param coverage the source {@link GridCoverage}
	 * @param subset   an instance of {@link GeneralEnvelope} that drives the crop
	 *                 operation.
	 * @return a cropped version of the source {@link GridCoverage}
	 */
	private List<GridCoverage2D> handleSubsettingExtension(GridCoverage2D coverage, WCSEnvelope subset, Hints hints) {

		List<GridCoverage2D> result = new ArrayList<GridCoverage2D>();
		if (subset != null) {
			if (subset.isCrossingDateline()) {
				Envelope2D coverageEnvelope = coverage.getEnvelope2D();
				GeneralEnvelope[] normalizedEnvelopes = subset.getNormalizedEnvelopes();
				for (int i = 0; i < normalizedEnvelopes.length; i++) {
					GeneralEnvelope ge = normalizedEnvelopes[i];
					if (ge.intersects(coverageEnvelope, false)) {
						GridCoverage2D cropped = cropOnEnvelope(coverage, ge);
						result.add(cropped);
					}
				}
			} else {
				GridCoverage2D cropped = cropOnEnvelope(coverage, subset);
				result.add(cropped);
			}
		}
		return result;
	}

	private GridCoverage2D cropOnEnvelope(GridCoverage2D coverage, Envelope cropEnvelope) {
		CoordinateReferenceSystem sourceCRS = coverage.getCoordinateReferenceSystem();
		CoordinateReferenceSystem subsettingCRS = cropEnvelope.getCoordinateReferenceSystem();
		try {
			if (!CRS.equalsIgnoreMetadata(subsettingCRS, sourceCRS)) {
				cropEnvelope = CRS.transform(cropEnvelope, sourceCRS);
			}
		} catch (TransformException e) {
			throw new WCS20Exception("Unable to initialize subsetting envelope",
					WCS20Exception.WCS20ExceptionCode.SubsettingCrsNotSupported, subsettingCRS.toWKT(), e);
		}

		GridCoverage2D cropped = WCSUtils.crop(coverage, cropEnvelope);
		cropped = GridCoverageWrapper.wrapCoverage(cropped, coverage, null, null, false);
		return cropped;
	}
}
