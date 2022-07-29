ARG EXIST_VERSION=6.0.1

# START STAGE 1
FROM openjdk:8-jdk-slim as builder

ARG FUSEKI_SERVER=fuseki:3030
ARG METRICS_SERVER=metrics:8030

USER root

ENV ANT_VERSION 1.10.12
ENV ANT_HOME /etc/ant-${ANT_VERSION}

WORKDIR /tmp

RUN apt-get update && apt-get install -y \
    git \
    curl

RUN curl -L -o apache-ant-${ANT_VERSION}-bin.tar.gz http://www.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mkdir ant-${ANT_VERSION} \
    && tar -zxvf apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mv apache-ant-${ANT_VERSION} ${ANT_HOME} \
    && rm apache-ant-${ANT_VERSION}-bin.tar.gz \
    && rm -rf ant-${ANT_VERSION} \
    && rm -rf ${ANT_HOME}/manual \
    && unset ANT_VERSION

ENV PATH ${PATH}:${ANT_HOME}/bin

WORKDIR /tmp/dracor-api
COPY . .
RUN sed -i "s/localhost:3030/${FUSEKI_SERVER}/" modules/config.xqm \
    && sed -i "s/localhost:8030/${METRICS_SERVER}/" modules/config.xqm \
    && ant \
    && curl -L -o /tmp/0-crypto.xar https://github.com/eXist-db/expath-crypto-module/releases/download/6.0.1/expath-crypto-module-6.0.1.xar \
    && curl -L -o /tmp/0-openapi.xar https://ci.de.dariah.eu/exist-repo/public/openapi-1.7.0.xar

FROM existdb/existdb:${EXIST_VERSION}

COPY --from=builder /tmp/*.xar /exist/autodeploy/
COPY --from=builder /tmp/dracor-api/build/dracor-*.xar /exist/autodeploy/

ENV DATA_DIR /exist-data

ENV JAVA_TOOL_OPTIONS \
    -Dfile.encoding=UTF8 \
    -Dsun.jnu.encoding=UTF-8 \
    -Djava.awt.headless=true \
    -Dorg.exist.db-connection.cacheSize=${CACHE_MEM:-256}M \
    -Dorg.exist.db-connection.pool.max=${MAX_BROKER:-20} \
    -Dlog4j.configurationFile=/exist/etc/log4j2.xml \
    -Dexist.home=/exist \
    -Dexist.configurationFile=/exist/etc/conf.xml \
    -Djetty.home=/exist \
    -Dexist.jetty.config=/exist/etc/jetty/standard.enabled-jetty-configs \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+UseCGroupMemoryLimitForHeap \
    -XX:+UseG1GC \
    -XX:+UseStringDeduplication \
    -XX:MaxRAMFraction=1 \
    -XX:+ExitOnOutOfMemoryError \
    -Dorg.exist.db-connection.files=${DATA_DIR} \
    -Dorg.exist.db-connection.recovery.journal-dir=${DATA_DIR}

# pre-populate the database by launching it once
RUN [ "java", \
    "org.exist.start.Main", "client", "-l", \
    "--no-gui",  "--xpath", "system:get-version()" ]
