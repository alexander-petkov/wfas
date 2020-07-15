FROM tomcat:8-jre8-alpine

ENV GEOSERVER_VERSION 2.16-SNAPSHOT
ENV GEOSERVER_DATA_DIR /opt/geoserver/data_dir 
ENV GEOSERVER_INSTALL_DIR /usr/local/broker

ENV BROKER_FILE geoserver-${GEOSERVER_VERSION}-activeMQ-broker-plugin.zip
ENV BROKER_URL http://build.geoserver.org/geoserver/2.16.x/community-latest/${BROKER_FILE}

#RUN apt-get update && apt-get install wget telnet  unzip -y
# GeoServer
#ADD conf/geoserver.xml /usr/local/tomcat/conf/Catalina/localhost/geoserver.xml
RUN mkdir -p /usr/local/tomcat/conf/Catalina/localhost && echo "<Context path=\"/broker\" docBase=\"/usr/local/broker\"></Context>" > /usr/local/tomcat/conf/Catalina/localhost/broker.xml \
        && mkdir -p ${GEOSERVER_DATA_DIR} \
	&& mkdir ${GEOSERVER_INSTALL_DIR} \
	&& cd ${GEOSERVER_INSTALL_DIR} \
	&& wget ${BROKER_URL} \
	&& unzip ${BROKER_FILE} \
	&& unzip activemqBroker-${GEOSERVER_VERSION}.war \
	&& rm *.war *.zip

# Tomcat environment
ENV CATALINA_OPTS "-server -Djava.awt.headless=true \
	-Xms768m -Xmx1560m -XX:+UseConcMarkSweepGC -XX:NewSize=48m \
	-DGEOSERVER_DATA_DIR=${GEOSERVER_DATA_DIR} \
        -Dactivemq.transportConnectors.server.uri=\"tcp://0.0.0.0:61666?maximumConnections=1000&wireFormat.maxFrameSize=104857600&jms.useAsyncSend=true&transport.daemon=true\""

#RUN apt-get remove wget telnet  unzip -y

#ADD start.sh /usr/local/bin/start.sh
CMD catalina.sh run

EXPOSE 61666
EXPOSE 8080
