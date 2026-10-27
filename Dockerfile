
# syntax=docker/dockerfile:1

# renovate: datasource=github-releases packageName=librenms/librenms versioning=semver
ARG LIBRENMS_VERSION="Dev"
ARG ALPINE_VERSION="3.24"
ARG SYSLOGNG_VERSION="4.11.0-r0"

FROM tianon/gosu:latest AS gosu

FROM crazymax/alpine-s6:${ALPINE_VERSION}-2.2.0.3

COPY --from=gosu /gosu /usr/local/bin/

# Install system dependencies and PHP 8.4
RUN apk --update --no-cache add \
    busybox-extras \
    acl \
    bash \
    bind-tools \
    binutils \
    ca-certificates \
    coreutils \
    curl \
    file \
    fping \
    git \
    graphviz \
    imagemagick \
    ipmitool \
    iputils \
    libcap-utils \
    mariadb-client \
    monitoring-plugins \
    mtr \
    net-snmp \
    net-snmp-tools \
    nginx \
    nmap \
    openssl \
    openssh-client \
    perl \
    php84 \
    php84-cli \
    php84-ctype \
    php84-curl \
    php84-dom \
    php84-fileinfo \
    php84-fpm \
    php84-gd \
    php84-gmp \
    php84-iconv \
    php84-json \
    php84-ldap \
    php84-mbstring \
    php84-mysqlnd \
    php84-opcache \
    php84-openssl \
    php84-pdo \
    php84-pdo_mysql \
    php84-pecl-memcached \
    php84-pear \
    php84-phar \
    php84-posix \
    php84-session \
    php84-simplexml \
    php84-snmp \
    php84-sockets \
    php84-tokenizer \
    php84-xml \
    php84-xmlwriter \
    php84-zip \
    php84-pecl-yaml \
    python3 \
    py3-pip \
    rrdtool \
    runit \
    sed \
    shadow \
    ttf-dejavu \
    tzdata \
    util-linux \
    whois \
    eudev-libs \
  && apk --update --no-cache add -t build-dependencies \
    build-base \
    make \
    mariadb-dev \
    musl-dev \
    python3-dev \
  && ln -sf /usr/bin/php84 /usr/bin/php \
  && pip3 install --upgrade --break-system-packages pip \
  && pip3 install \
    python-memcached \
    mysqlclient \
    ansible \
    --upgrade --break-system-packages \
  && curl -sSL https://getcomposer.org/installer \
    | php -- --install-dir=/usr/bin --filename=composer \
  && apk del build-dependencies \
  && rm -rf /var/www/* /tmp/* \
  && echo "/usr/sbin/fping -6 \$@" > /usr/sbin/fping6 \
  && chmod +x /usr/sbin/fping6 \
  && chmod u+s,g+s \
    /bin/ping \
    /bin/ping6 \
    /usr/lib/monitoring-plugins/check_icmp \
  && setcap cap_net_raw+ep /usr/bin/nmap \
  && setcap cap_net_raw+ep /usr/sbin/fping \
  && setcap cap_net_raw+ep /usr/sbin/fping6 \
  && setcap cap_net_raw+ep /usr/lib/monitoring-plugins/check_icmp \
  && setcap cap_net_raw+ep /usr/lib/monitoring-plugins/check_ping

# Install the pinned syslog-ng package separately
ARG SYSLOGNG_VERSION
RUN apk --update --no-cache add "syslog-ng=${SYSLOGNG_VERSION}"

ENV S6_BEHAVIOUR_IF_STAGE2_FAILS="2" \
    LIBRENMS_PATH="/opt/librenms" \
    LIBRENMS_DOCKER="1" \
    TZ="UTC" \
    PUID="1000" \
    PGID="1000"

# Create the LibreNMS runtime user and install distro detection
RUN addgroup -g ${PGID} librenms \
  && adduser -D \
    -h /home/librenms \
    -u ${PUID} \
    -G librenms \
    -s /bin/sh \
    librenms \
  && curl -fsSL \
    https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro \
    -o /usr/bin/distro \
  && chmod +x /usr/bin/distro

WORKDIR ${LIBRENMS_PATH}

ARG LIBRENMS_VERSION
ARG WEATHERMAP_PLUGIN_COMMIT

# Build Telequill LibreNMS
RUN apk --update --no-cache add -t build-dependencies \
    build-base \
    linux-headers \
    musl-dev \
    python3-dev \
  && echo "Installing Telequill from version ${LIBRENMS_VERSION}..." \
  && git clone --depth=1 \
    --branch "${LIBRENMS_VERSION}" \
    https://github.com/alphabridgetech/librenms.git . \
  && pip3 install \
    --ignore-installed \
    -r requirements.txt \
    --upgrade \
    --break-system-packages \
  && mkdir -p config.d \
  && cp config.php.default config.php \
  && cp snmpd.conf.example /etc/snmp/snmpd.conf \
  && sed -i '/runningUser/d' lnms \
  && echo 'foreach (glob("/data/config/*.php") as $filename) include $filename;' >> config.php \
  && echo "foreach (glob(\"${LIBRENMS_PATH}/config.d/*.php\") as \$filename) include \$filename;" >> config.php \
  && chown -R librenms:librenms "${LIBRENMS_PATH}" \
  && su librenms -s /bin/sh -c \
    'COMPOSER_CACHE_DIR=/tmp composer install --no-dev --no-interaction --no-ansi' \
  && apk del build-dependencies \
  && rm -rf \
    .git \
    html/plugins/Test \
    doc/ \
    tests/ \
    /tmp/* \
  && python3 -m venv /opt/librenms/librenms-ansible-inventory-plugin \
  && /opt/librenms/librenms-ansible-inventory-plugin/bin/pip install \
    paramiko==3.2.0

# Copy Telequill runtime configuration and service scripts
COPY rootfs /

EXPOSE 8000 514 514/udp 162 162/udp

VOLUME ["/data"]

ENTRYPOINT ["/init"]
