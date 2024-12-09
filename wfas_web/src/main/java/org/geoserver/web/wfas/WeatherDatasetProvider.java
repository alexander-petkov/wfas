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

import java.util.Iterator;
import java.util.List;
import org.geoserver.web.wicket.GeoServerDataProvider;

/**
 * Implementation of IDataProvider that retrieves contacts from the contact database.
 *
 * @author apetkov
 */
public class WeatherDatasetProvider extends GeoServerDataProvider<WeatherDatasetInfo> {
    private static final long serialVersionUID = 1L;
    private WeatherDatasetDatabase wdb;
    public static Property<WeatherDatasetInfo> ID =
            new AbstractProperty<WeatherDatasetInfo>("id") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getId();
                }
            };
    public static Property<WeatherDatasetInfo> ABBREV =
            new AbstractProperty<WeatherDatasetInfo>("abbreviation") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getAbbreviation();
                }
            };
    public static Property<WeatherDatasetInfo> NAME =
            new AbstractProperty<WeatherDatasetInfo>("name") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getName();
                }
            };
    public static Property<WeatherDatasetInfo> COVERAGE =
            new AbstractProperty<WeatherDatasetInfo>("spatial coverage") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getSpatialCoverage();
                }
            };
    public static Property<WeatherDatasetInfo> TYPE =
            new AbstractProperty<WeatherDatasetInfo>("type") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getType();
                }
            };
    public static Property<WeatherDatasetInfo> LAYERS =
            new AbstractProperty<WeatherDatasetInfo>("layers") {

                private static final long serialVersionUID = 1L;

                @Override
                public Object getPropertyValue(WeatherDatasetInfo item) {
                    return item.getLayers();
                }
            };

    static List<Property<WeatherDatasetInfo>> PROPERTIES =
            List.of(ID, ABBREV, NAME, COVERAGE, LAYERS);

    public WeatherDatasetProvider() {
        wdb = new WeatherDatasetDatabase();
    }

    protected WeatherDatasetDatabase getDatasets() {
        try {
            return wdb; // org.geoserver.web.wfas.DatabaseLocator.getDatabase();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    /**
     * retrieves contacts from database starting with index <code>first</code> and ending with
     * <code>first+count</code>
     *
     * @see org.apache.wicket.markup.repeater.data.IDataProvider#iterator(long, long)
     */
    @Override
    public Iterator<WeatherDatasetInfo> iterator(long first, long count) {
        return getDatasets().find(first, count, this.getSort()).iterator();
    }

    /**
     * returns total number of datasets
     *
     * @see org.apache.wicket.markup.repeater.data.IDataProvider#size()
     */
    @Override
    public long size() {
        return getDatasets().getCount();
    }

    @Override
    protected List<Property<WeatherDatasetInfo>> getProperties() {
        // TODO Auto-generated method stub
        return WeatherDatasetProvider.PROPERTIES;
    }

    @Override
    protected List<WeatherDatasetInfo> getItems() {
        // TODO Auto-generated method stub
        return getDatasets().find(0, getDatasets().getCount(), this.getSort());
    }
}
