FROM wfas/wfas-repo/tomcat-8-jre8-alpine

ENV CATALINA_HOME /usr/local/tomcat 
ENV GEOSERVER_VERSION  2.16.2 
ENV GEOSERVER_MAJOR_VERSION 2.16   
ENV GEOSERVER_WAR_URL  http://downloads.sourceforge.net/project/geoserver/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip 
ENV GEOSERVER_EXT_URL https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/extensions 
ENV GEOSERVER_COMM_EXT_URL https://build.geoserver.org/geoserver/${GEOSERVER_MAJOR_VERSION}.x/community-latest
ENV GEOSERVER_DIR  ${CATALINA_HOME}/webapps/geoserver
ENV GEOSERVER_EXT_DIR  ${GEOSERVER_DIR}/WEB-INF/lib 
ENV GEOSERVER_DATA_DIR /data 
ENV GDAL_DATA /usr/share/gdal
#ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:/usr/lib

RUN apk update \
  && apk add --no-cache unzip \
  #&& apk add --no-cache \
  #  icu-libs \
  #  json-c \
  #  poppler \  
  && apk add --no-cache java-gdal \
  && cd /tmp \
  && rm -rf ${CATALINA_HOME}/webapps/* \
  && mkdir -p ${GEOSERVER_DATA_DIR} ${GEOSERVER_DIR}\
  && wget -qO /tmp/geoserver.zip ${GEOSERVER_WAR_URL} \
  && unzip -qq /tmp/geoserver.zip \
  && unzip -qqo -d ${GEOSERVER_DIR} /tmp/geoserver.war \
  && for ext in wps gdal grib netcdf; \
     do \
        wget -q $GEOSERVER_EXT_URL/geoserver-${GEOSERVER_VERSION}-${ext}-plugin.zip ; \
        unzip -qo -d ${GEOSERVER_EXT_DIR} geoserver-${GEOSERVER_VERSION}-${ext}-plugin.zip ; \
     done \
  && for comm_ext in jms-cluster ncwms ; \
     do \
         wget -q "${GEOSERVER_COMM_EXT_URL}/geoserver-${GEOSERVER_MAJOR_VERSION}-SNAPSHOT-${comm_ext}-plugin.zip" ; \
         unzip -qo -d ${GEOSERVER_EXT_DIR} geoserver-${GEOSERVER_MAJOR_VERSION}-SNAPSHOT-${comm_ext}-plugin.zip ; \
     done \ 
  && cp /usr/share/java/gdal-3.1.0.jar $GEOSERVER_EXT_DIR/gdal-2.2.0.jar \
  && rm -rf /tmp/* \
  && rm -rf /var/lib/apt/lists/*

VOLUME ${GEOSERVER_DATA_DIR}

WORKDIR ${CATALINA_HOME}

COPY setenv.sh.tpl ${CATALINA_HOME}/bin/setenv.sh
COPY wxs_wps-1.0.jar ${GEOSERVER_EXT_DIR} 
# Used a different sed delimiter because of https://github.com/moby/moby/issues/32140
RUN sed -i -r "s|%%GEOSERVER_DATA_DIR%%|${GEOSERVER_DATA_DIR}|" \
    ${CATALINA_HOME}/bin/setenv.sh
