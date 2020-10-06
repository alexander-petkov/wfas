FROM wfas/wfas-repo:tomcat-8-jre8-alpine

ENV CATALINA_HOME /usr/local/tomcat 
ENV GEOSERVER_VERSION  2.18.0 
ENV GEOSERVER_MAJOR_VERSION 2.18
ENV INITIAL_MEMORY 8G
ENV MAXIMUM_MEMORY 16G
ENV GEOSERVER_WAR_URL  http://downloads.sourceforge.net/project/geoserver/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip 
ENV GEOSERVER_EXT_URL https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions 
ENV GEOSERVER_COMM_EXT_URL https://build.geoserver.org/geoserver/${GEOSERVER_MAJOR_VERSION}.x/community-latest
ENV GEOSERVER_DIR  ${CATALINA_HOME}/webapps/geoserver
ENV GEOSERVER_EXT_DIR  ${GEOSERVER_DIR}/WEB-INF/lib 
ENV GEOSERVER_DATA_DIR /opt/geoserver/data_dir
ENV GEOSERVER_LOG_DIR /opt/geoserver/logs
ENV GEOSERVER_LOG_LOCATION=${GEOSERVER_LOG_DIR}/geoserver.log
ENV GEOSERVER_OPTS="-Djava.awt.headless=true -server -Xms${INITIAL_MEMORY} -Xmx${MAXIMUM_MEMORY} \
	-Xrs -XX:PerfDataSamplingInterval=500 \
	-Dorg.geotools.referencing.forceXY=true -XX:SoftRefLRUPolicyMSPerMB=36000 -XX:+UseParallelGC -XX:NewRatio=2 \
	-XX:+CMSClassUnloadingEnabled -Dfile.encoding=UTF8 -Duser.timezone=GMT -Djavax.servlet.request.encoding=UTF-8 \
	-Djavax.servlet.response.encoding=UTF-8 \
	-Dorg.geotools.shapefile.datetime=true"
ENV GDAL_DATA /usr/share/gdal

RUN apk update \
  && apk add --no-cache unzip ttf-ubuntu-font-family \
  && apk add --no-cache java-gdal \
  && cd /tmp \
  && rm -rf ${CATALINA_HOME}/webapps/* \
  && mkdir -p ${GEOSERVER_DATA_DIR} ${GEOSERVER_DIR} \
	${GEOSERVER_LOG_DIR} \
  && wget -qO /tmp/geoserver.zip ${GEOSERVER_WAR_URL} \
  && unzip -qq /tmp/geoserver.zip \
  && unzip -qqo -d ${GEOSERVER_DIR} /tmp/geoserver.war \
  && for ext in wps gdal grib netcdf netcdf-out wcs2_0-eo; \
     do \
        wget -q $GEOSERVER_EXT_URL/geoserver-${GEOSERVER_VERSION}-${ext}-plugin.zip ; \
        unzip -qo -d ${GEOSERVER_EXT_DIR} geoserver-${GEOSERVER_VERSION}-${ext}-plugin.zip ; \
     done \
  && for comm_ext in jms-cluster ncwms ; \
     do \
         wget -q "${GEOSERVER_COMM_EXT_URL}/geoserver-${GEOSERVER_MAJOR_VERSION}-SNAPSHOT-${comm_ext}-plugin.zip" ; \
         unzip -qo -d ${GEOSERVER_EXT_DIR} geoserver-${GEOSERVER_MAJOR_VERSION}-SNAPSHOT-${comm_ext}-plugin.zip ; \
     done \ 
  && cp /usr/share/java/gdal-3.1.2.jar $GEOSERVER_EXT_DIR/gdal-2.2.0.jar \
  && mv $GEOSERVER_EXT_DIR/postgresql-*.jar $CATALINA_HOME/lib/ \
  && rm -rf /tmp/* \
  && rm -rf /var/lib/apt/lists/*

WORKDIR ${CATALINA_HOME}

COPY setenv.sh.tpl ${CATALINA_HOME}/bin/setenv.sh
COPY wxs_wps-1.0.jar ${GEOSERVER_EXT_DIR} 
COPY context.xml $CATALINA_HOME/conf
COPY server.xml $CATALINA_HOME/conf
COPY cacerts /etc/ssl/certs/java/cacerts
# Used a different sed delimiter because of https://github.com/moby/moby/issues/32140
RUN sed -i -r "s|%%GEOSERVER_DATA_DIR%%|${GEOSERVER_DATA_DIR}|" \
    ${CATALINA_HOME}/bin/setenv.sh
