ARG APPDAEMON_VERSION
FROM acockburn/appdaemon:${APPDAEMON_VERSION}

ARG QOLSYSGW_VERSION
ARG QOLSYSGW_STRIP
RUN curl -fsSL "https://github.com/xaf/qolsysgw/archive/refs/${QOLSYSGW_VERSION}.tar.gz" \
    | tar -zxv --strip-components=1 -C / ${QOLSYSGW_STRIP}/apps/
