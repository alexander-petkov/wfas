CATALINA_OPTS="${CATALINA_OPTS} -DGEOSERVER_DATA_DIR=%%GEOSERVER_DATA_DIR%% \
		-Dpostgres.addr=${POSTGRES_ADDR} \
		-Dpostgres.port=${POSTGRES_PORT} \
		-Dproxy.name=${PROXY_NAME} \
		-Dproxy.https.port=${PROXY_HTTPS_PORT} \
		-Ddbname=${DBNAME} ${GEOSERVER_OPTS}"
