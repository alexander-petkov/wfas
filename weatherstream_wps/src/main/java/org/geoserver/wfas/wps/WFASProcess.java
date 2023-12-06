package org.geoserver.wfas.wps;

import java.io.IOException;

import org.geoserver.catalog.Catalog;
import org.geoserver.catalog.CoverageInfo;
import org.geoserver.wps.gs.GeoServerProcess;
import org.geotools.coverage.grid.io.StructuredGridCoverage2DReader;
import org.geotools.geometry.jts.JTS;
import org.geotools.geometry.jts.JTSFactoryFinder;
import org.geotools.referencing.CRS;
import org.geotools.util.factory.FactoryRegistryException;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.Point;
import org.geotools.api.coverage.grid.GridCoverageReader;
import org.geotools.api.referencing.crs.CoordinateReferenceSystem;
import org.geotools.api.referencing.operation.MathTransform;

public class WFASProcess implements GeoServerProcess {
	protected Catalog catalog;
	protected Point input;
	protected Point transPoint;
	protected static String LANDFIRE_NAMESPACE = "landfire";
	protected static String LANDFIRE_DEM = "us_dem_2016";	
	protected static String OSM_NAMESPACE = "osm";

	/**
	 * GeometryFactory will be used
	 * to create a Point geometry   
	 * from user input coordinates
	 */
	protected GeometryFactory geometryFactory = JTSFactoryFinder.getGeometryFactory();
	
	/**
	 * Default constructor
	 * @param catalog
	 */
	public WFASProcess(Catalog catalog) {
		this.catalog = catalog;
	}

	/**
	 * Utility method for translating a 
	 * Point to another CRS
	 * @param input Point to be translated
	 * @param targetCRS
	 * @return transPoint translated point 
	 */
	protected Point transformPoint(Point inputPoint, CoordinateReferenceSystem targetCRS) {
		MathTransform transform;
		Point transPoint = null;
		try { 
			transform =
						CRS.findMathTransform(CRS.decode("EPSG:" + inputPoint.getSRID()), targetCRS);
				transPoint = (Point) JTS.transform(inputPoint, transform);
				transPoint.setSRID(Integer.parseInt(CRS.toSRS(targetCRS,true)));
		} catch (Exception e) { 
			//TODO Auto-generated catch block e.printStackTrace(csvWriter); }
		}
		return transPoint;
	}//end transformPoint

	/**
	 * Returns a JTS Point in Geographic Projection
	 * @param longitude TODO
	 * @param latitude TODO
	 * @return JTS Point
	 * @throws FactoryRegistryException
	 */
	protected Point createPoint(double longitude, double latitude) throws FactoryRegistryException {
		Point p = JTSFactoryFinder.getGeometryFactory()
				.createPoint(new Coordinate(longitude,latitude));
		p.setSRID(4326);
		return p;
	}
	
	/**
	 * @param ci CoverageInfo
	 * @return reader StructuredGridCoverage2DReader
	 */
	protected StructuredGridCoverage2DReader getCoverageReader(CoverageInfo ci) {
		GridCoverageReader genericReader = null;
		try {
			genericReader = ci.getGridCoverageReader(null, null);
		} catch (IOException e1) {
			// TODO Auto-generated catch block
			e1.printStackTrace();
		} 
		// we have a descriptor, now we need to find the association between the exposed 
		//dimension names and the granule source attributes
		StructuredGridCoverage2DReader reader = null; 
		try { 
			reader = (StructuredGridCoverage2DReader) genericReader; 
		} catch (ClassCastException e) { 
			// TODO Auto-generated catch block break; }
		}
		return reader;
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
}

