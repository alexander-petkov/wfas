/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.geoserver.web.wfas;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Objects;
import org.apache.wicket.util.io.IClusterable;

/**
 * domain object for demonstrations.
 *
 * @author igor
 */
public class WeatherDatasetInfo implements IClusterable {
    private static final long serialVersionUID = 1L;

    private long id;

    private String abbreviation;

    private String name;

    private String spatial_coverage;

    public String getSpatialCoverage() {
        return spatial_coverage;
    }

    public void setSpatialCoverage(String spatial_coverage) {
        this.spatial_coverage = spatial_coverage;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    private Date last_update;

    private String type;

    private int num_layers;

    private List<String> layers;

    /** Constructor */
    public WeatherDatasetInfo() {}

    @Override
    public String toString() {
        return "[Dataset id="
                + id
                + " abbreviation="
                + abbreviation
                + " name="
                + name
                + " spatial coverage="
                + spatial_coverage
                + " last update="
                + last_update.toString()
                + " type="
                + type
                + " # of layers="
                + layers
                + "]";
    }

    @Override
    public int hashCode() {
        return Objects.hash(abbreviation, id, last_update, layers, name, spatial_coverage, type);
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj) return true;
        if (obj == null) return false;
        if (getClass() != obj.getClass()) return false;
        WeatherDatasetInfo other = (WeatherDatasetInfo) obj;
        return Objects.equals(abbreviation, other.abbreviation)
                && id == other.id
                && Objects.equals(last_update, other.last_update)
                && layers == other.layers
                && Objects.equals(name, other.name)
                && Objects.equals(spatial_coverage, other.spatial_coverage)
                && Objects.equals(type, other.type);
    }

    /** @param id */
    public void setId(long id) {
        this.id = id;
    }

    /** @return id */
    public long getId() {
        return id;
    }

    public void setLayers(List layers) {
        this.layers = layers;
    }

    public List getLayers() {
        return layers;
    }

    /**
     * Constructor
     *
     * @param ResultSet rs
     * @throws SQLException
     */
    public WeatherDatasetInfo(ResultSet rs) throws SQLException {
        this.setId(rs.getLong("id"));
        this.setAbreviation(rs.getString("abbreviation"));
        this.setName(rs.getString("name"));
        this.setLastUpdate(rs.getDate("last_update"));
        this.setNumLayers(rs.getInt("layers"));
        this.setSpatialCoverage(rs.getString("spatial_coverage"));
        this.setType(rs.getString("type"));
        /*
         * TODO:
         * build layers list from the database
         */
        this.setLayers(
                Arrays.asList(
                        "Cloud_cover",
                        "Relative_humidity",
                        "Solar_radiation",
                        "Temperature",
                        "Total_precipitation",
                        "Wind_direction",
                        "Wind_speed"));
    }

    /** @return cellPhone */
    public String getAbbreviation() {
        return abbreviation;
    }

    /** @param cellPhone */
    public void setAbreviation(String abbrev) {
        this.abbreviation = abbrev;
    }

    /** @return firstName */
    public String getName() {
        return name;
    }

    /** @param firstName */
    public void setName(String name) {
        this.name = name;
    }

    /** @return last_update */
    public Date getLastUpdate() {
        return last_update;
    }

    /** @param Date last_update */
    public void setLastUpdate(Date update) {
        this.last_update = update;
    }

    /** @return layers */
    public int getNumLayers() {
        return num_layers;
    }

    /** @param layers */
    public void setNumLayers(int numLayers) {
        this.num_layers = numLayers;
    }
}
