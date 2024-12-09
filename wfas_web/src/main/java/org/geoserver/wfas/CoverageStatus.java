package org.geoserver.wfas;

import java.io.IOException;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.geoserver.catalog.CoverageInfo;
import org.geotools.coverage.grid.io.GridCoverage2DReader;

/**
 * A class to determine and disclose the status of a Coverage in a dataset
 *
 * <p>The number of granules in the mosaic should correspond to number of files on disk
 *
 * @author apetkov Alexander Petkov
 */
public class CoverageStatus {

    private static final Logger LOGGER = Logger.getLogger(CoverageStatus.class.toString());

    /** coverage status */
    boolean statusOK;

    /** number of mosaic granules */
    int numGranules;

    /** number of files on disk */
    int numFiles;

    List<Path> result = null;

    public CoverageStatus(CoverageInfo ci) throws IOException {

        String timelist =
                ci.getGridCoverageReader(null, null)
                        .getMetadataValue(GridCoverage2DReader.TIME_DOMAIN);
        setNumGranules(Arrays.asList(timelist.split(",")).size());
        String diskPath = (new URL(ci.getStore().getURL())).getPath();
        if (!Paths.get(diskPath).isAbsolute()) {
            throw new IOException("Need absolute path");
        }
        getDiskGranules(diskPath);
        setNumFiles(result.size());
        setStatusOK(getNumGranules() == getNumFiles());
    }

    /**
     * Constructor using a JNDI connection for database lookup
     *
     * @author apetkov
     * @param namespace
     * @param coverage
     * @throws SQLException
     */
    //    public CoverageStatus(String namespace, String coverage) throws SQLException {
    //        JNDIConnector jc = new JNDIConnector();
    //        Connection conn = jc.getConnection();
    //        Statement sql = conn.createStatement();
    //        ResultSet rs =
    //                sql.executeQuery(
    //                        "SELECT count(*) as numgranules from "
    //                                + namespace
    //                                + ".\""
    //                                + coverage
    //                                + "\"");
    //
    //        setNumGranules(rs.getInt(0));
    //        getDiskGranules(namespace, coverage);
    //        setNumFiles(result.size());
    //        setStatusOK(getNumGranules() == getNumFiles());
    //        /** Close resources: */
    //        rs.close();
    //        sql.close();
    //        conn.close();
    //        jc.close();
    //    }

    public boolean isStatusOK() {
        return statusOK;
    }

    public void setStatusOK(boolean statusOK) {
        this.statusOK = statusOK;
    }

    public int getNumGranules() {
        return numGranules;
    }

    public void setNumGranules(int numGranules) {
        this.numGranules = numGranules;
    }

    public int getNumFiles() {
        return numFiles;
    }

    public void setNumFiles(int numFiles) {
        this.numFiles = numFiles;
    }

    /**
     * @param nameSpace
     * @param coverage
     */
    private void getDiskGranules(String granulePath) {
        result = findFiles(granulePath.toString(), ".tif");
        if (LOGGER.isLoggable(Level.INFO)) {
            LOGGER.log(Level.INFO, "Found " + result.size() + " granules");
        }
    }

    /**
     * @param path
     * @param pattern
     * @return result
     */
    private List<Path> findFiles(String path, String pattern) {
        if (LOGGER.isLoggable(Level.INFO)) {
            LOGGER.log(Level.INFO, "Searching for " + pattern + " pattern in " + path);
        }

        try (Stream<Path> pathStream = Files.walk(Paths.get(path))) {
            result =
                    pathStream
                            .filter(Files::isRegularFile) // is a file
                            .filter(p -> p.getFileName().toString().endsWith(pattern))
                            .collect(Collectors.toList());
            pathStream.close();
        } catch (IOException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
        return result;
    }
}
