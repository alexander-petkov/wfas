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

import java.io.Serializable;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;
import javax.sql.DataSource;
import org.apache.wicket.extensions.markup.html.repeater.util.SortParam;
import org.springframework.jndi.JndiTemplate;

/**
 * simple database for WFAS datasets, pulled from Postgres JNDI source
 *
 * @author apetkov
 */
public class WeatherDatasetDatabase implements Serializable {
    private static final long serialVersionUID = 2617717514946729039L;
    private final Map<Long, WeatherDatasetInfo> map = Collections.synchronizedMap(new HashMap<>());
    private final List<WeatherDatasetInfo> ascIdx = Collections.synchronizedList(new ArrayList<>());
    private final List<WeatherDatasetInfo> descIdx =
            Collections.synchronizedList(new ArrayList<>());
    private JndiTemplate jndiTemplate = new JndiTemplate();
    private Context initContext = null;
    private Context envContext = null;
    private DataSource ds = null;
    private Connection conn = null;
    private Statement statement = null;
    private String sql =
            "select id, abbreviation, name, "
                    + "num_granules,  spatial_coverage, type, last_update, layers "
                    + "from dataset_index";

    /** Constructor */
    public WeatherDatasetDatabase() {
        jndiTemplate = new JndiTemplate();
        ResultSet rs = null;
        try {
            initContext = (InitialContext) jndiTemplate.getContext();
            envContext = (Context) initContext.lookup("java:comp/env");
            ds = (DataSource) envContext.lookup("jdbc/postgres");
        } catch (NamingException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }

        try {
            conn = ds.getConnection();
            statement = conn.createStatement();
            rs = statement.executeQuery(sql);
        } catch (SQLException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }

        try {
            while (rs.next()) {
                add(new WeatherDatasetInfo(rs));
            }
            rs.close();
        } catch (SQLException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        } finally {
            try {
                statement.close();
                conn.close();
                conn = null;
                ds = null;
                envContext = null;
                initContext = null;
                jndiTemplate = null;
                statement = null;
                sql = null;
                rs.close();
            } catch (Exception e) {
            } // end try
        } // end finally;
    }

    /**
     * find dataset by id
     *
     * @param id
     * @return dataset
     */
    public WeatherDatasetInfo get(long id) {
        WeatherDatasetInfo c = map.get(id);
        if (c == null) {
            throw new RuntimeException("dataset with id [" + id + "] not found in the database");
        }
        return c;
    }

    protected void add(final WeatherDatasetInfo weatherDS) {
        map.put(weatherDS.getId(), weatherDS);
        ascIdx.add(weatherDS);
        descIdx.add(weatherDS);
    }

    /**
     * select datasets and apply sort
     *
     * @param first
     * @param count
     * @param sort
     * @return list of datasets
     */
    public List<WeatherDatasetInfo> find(long first, long count, SortParam sort) {
        return getIndex(sort).subList((int) first, (int) (first + count));
    }

    public List<WeatherDatasetInfo> getIndex(SortParam<?> sort) {
        if (sort == null) {
            return ascIdx;
        }

        updateIndecies(sort);
        return sort.isAscending() ? ascIdx : descIdx;
    }

    /** @return number of datasets in the database */
    public int getCount() {
        return ascIdx.size();
    }

    private void updateIndecies(SortParam<?> sort) {

        switch (sort.getProperty().toString()) {
            case "id":
                {
                    Collections.sort(
                            ascIdx,
                            (arg0, arg1) -> ((Long) (arg0.getId())).compareTo(arg1.getId()));
                    Collections.sort(
                            descIdx,
                            (arg0, arg1) -> ((Long) (arg1).getId()).compareTo((arg0).getId()));
                }
            case "abbrevation":
                {
                    Collections.sort(
                            ascIdx,
                            (arg0, arg1) ->
                                    (arg0.getAbbreviation().compareTo(arg1.getAbbreviation())));
                    Collections.sort(
                            descIdx,
                            (arg0, arg1) ->
                                    (arg1).getAbbreviation().compareTo((arg0).getAbbreviation()));
                }
            case "name":
                {
                    Collections.sort(
                            ascIdx, (arg0, arg1) -> (arg0.getName().compareTo(arg1.getName())));
                    Collections.sort(
                            descIdx, (arg0, arg1) -> (arg1.getName().compareTo((arg0).getName())));
                }
            default:
                {
                }
        }
    }
}
