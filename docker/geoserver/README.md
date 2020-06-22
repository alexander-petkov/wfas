# docker-geoserver

This repository contains a collection of templated `Dockerfile`s for image variants designed to run GeoServer using the Apache Tomcat Java servlet container.

## Usage

### Template Variables

- `TOMCAT_VERSION` - Tomcat version. For `tomcat:*-jre*-slim` or `tomcat:*-jre*-alpine` [images](https://hub.docker.com/_/tomcat/) (`7`, `8`, or `9`).
- `GEOSERVER_VERSION` - Version number of the target GeoServer instance (`2.11.2`)
- `JRE_VERSION` - Java Runtime Environment version (`8`).
- `VARIANT` - Base container image variant (`alpine` or `slim`)

### Testing

An example of how to use `cibuild` to build and test an image:

```bash
$ CI=1 GEOSERVER_VERSION=2.11.2 TOMCAT_VERSION=7 JRE_VERSION=8 VARIANT=slim \
  ./scripts/cibuild
```

### Customizing the GeoServer
 If you have an existing [GeoServer data directory](https://docs.geoserver.org/stable/en/user/datadirectory/index.html), you can use it with this image by mounting it at `/data`:

```bash
$ docker run -d -p 8080:8080 -v /path/to/geoserver/data:/data quay.io/azavea/geoserver:2.11.2-tomcat8-jre8-alpine
```

## Contributing
To add a new GeoServer version to the build matrix, do the following:
- Download .zip files containing the GeoServer WAR and the monitoring plugin from `http://geoserver.org/release/GEOSERVER_VERSION`, where `GEOSERVER_VERSION` is the version of GeoServer you wish to install. Make sure that the filenames are as follows (you should rename them, if necessary):
    - Geoserver WAR: `geoserver-$GEOSERVER_VERSION-war.zip`
    - Geoserver monitor plugin: `geoserver-$GEOSERVER_VERSION-monitor-plugin.zip`
- Upload the ZIP files to this Project's `0.0.0` release at https://github.com/azavea/docker-geoserver/releases/edit/0.0.0.
- Add entries to [.travis.yml](./.travis.yml) build matrix for each `GEOSERVER_VERSION`, `TOMCAT_VERSION`, `JRE_VERSION` and both `VARIANT`s.

- Follow the instructions in the [testing](#testing) section to ensure that the build works.