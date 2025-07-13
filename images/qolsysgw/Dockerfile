ARG APPDAEMON_VERSION
FROM acockburn/appdaemon:${APPDAEMON_VERSION}

ARG QOLSYSGW_VERSION
RUN curl -fsSL "https://github.com/xaf/qolsysgw/archive/refs/tags/v${QOLSYSGW_VERSION}.tar.gz" \
    | tar -zxv --strip-components=1 -C / qolsysgw-${QOLSYSGW_VERSION}/apps/
