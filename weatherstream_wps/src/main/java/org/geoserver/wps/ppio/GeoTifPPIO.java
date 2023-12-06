package org.geoserver.wps.ppio;

import org.geoserver.wps.resource.WPSResourceManager;

public class GeoTifPPIO extends GeoTiffPPIO   {
	protected GeoTifPPIO(WPSResourceManager resources) {
		super(resources);
		super.mimeType = "image/tif";
    }
	@Override
    public String getFileExtension() {
        return "tif";
    }
	
}
