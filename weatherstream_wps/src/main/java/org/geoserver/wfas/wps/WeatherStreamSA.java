package org.geoserver.wfas.wps;

import java.util.Arrays;

import org.geoserver.catalog.Catalog;
import org.locationtech.jts.geom.Point;

public class WeatherStreamSA extends WeatherStream {

	public WeatherStreamSA(Catalog catalog) {
		super(catalog);
		dem = catalog.getCoverageByName("nasa", "bolivia_dem");
		// TODO Auto-generated constructor stub
	}

	@Override
	protected void setNameSpaceList(String archive) {
		// TODO Auto-generated method stub
		namespaces = Arrays.asList("gfs_sa");
	}

	@Override
	protected String getTimeZoneId(Point p) {
		return "GMT-4";
	}
	
}
