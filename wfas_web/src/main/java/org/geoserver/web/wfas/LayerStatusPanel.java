package org.geoserver.web.wfas;

import java.io.IOException;
import org.apache.wicket.markup.html.basic.Label;
import org.apache.wicket.markup.html.basic.MultiLineLabel;
import org.apache.wicket.markup.html.panel.Panel;
import org.geoserver.catalog.CoverageInfo;
import org.geoserver.web.GeoServerApplication;
import org.geoserver.wfas.CoverageStatus;

public class LayerStatusPanel extends Panel {

    private static final long serialVersionUID = -4308612602502348890L;

    public LayerStatusPanel(String id, String workspace, String layer) throws IOException {
        super(id);
        GeoServerApplication app = (GeoServerApplication) getApplication();
        CoverageInfo ci = app.getCatalog().getCoverageByName(workspace, layer);
        CoverageStatus cs = new CoverageStatus(ci);
        add(new Label("coverage_name", workspace + ":" + layer));
        add(
                new MultiLineLabel(
                                "status",
                                "Number of mosaic granules: "
                                        + cs.getNumGranules()
                                        + "\n"
                                        + "Number of files on disk : "
                                        + cs.getNumFiles()
                                        + "\n"
                                        + "Status OK: "
                                        + (cs.isStatusOK()
                                                ? "<font color=\"green\">yes</font>"
                                                : "<font color=\"red\">no</font>"))
                        .setEscapeModelStrings(false));
    }
}
