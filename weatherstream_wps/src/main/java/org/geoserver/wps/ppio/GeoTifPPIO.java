package org.geoserver.wps.ppio;

public class GeoTifPPIO extends GeoTiffPPIO   {
	protected GeoTifPPIO() {
		super.mimeType = "image/tif";
    }
	@Override
    public String getFileExtension() {
        return "tif";
    }
}
