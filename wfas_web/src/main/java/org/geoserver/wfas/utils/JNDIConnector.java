package org.geoserver.wfas.utils;

import java.sql.Connection;
import java.sql.SQLException;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingException;
import javax.sql.DataSource;
import org.springframework.jndi.JndiTemplate;

public class JNDIConnector {
    private JndiTemplate jndiTemplate = new JndiTemplate();
    private Context initContext = null;
    private Context envContext = null;
    private DataSource ds = null;
    private Connection conn = null;

    public JNDIConnector() {
        jndiTemplate = new JndiTemplate();
        try {
            initContext = (InitialContext) jndiTemplate.getContext();
            envContext = (Context) initContext.lookup("java:comp/env");
            ds = (DataSource) envContext.lookup("jdbc/postgres");
        } catch (NamingException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
    }

    public Connection getConnection() {
        try {
            conn = ds.getConnection();
        } catch (SQLException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
        return conn;
    }

    /** Close all resources */
    public void close() {
        try {
            conn.close();
        } catch (SQLException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
        conn = null;
        ds = null;
        envContext = null;
        initContext = null;
        jndiTemplate = null;
    }
}
