FROM debian:13-slim

ARG TARGETPLATFORM
ARG AMP3_STREAM=preview
ARG AMP3_REPO=https://cdn-repo.c7rs.com/amp3

ENV container=docker \
    TZ=Etc/UTC \
    PORT=8443 \
    AMP3_STREAM=${AMP3_STREAM} \
    AMP3_REPO=${AMP3_REPO} \
    AMP3_ORIGIN=https://cdn-downloads.c7rs.com/AMP3 \
    SYSTEMD_LOG_TARGET=console \
    SYSTEMD_LOG_LEVEL=info

ARG DEBIAN_FRONTEND=noninteractive

# The AMP 3 beta installer currently supports x86_64 only.
RUN if [ "$TARGETPLATFORM" != "linux/amd64" ]; then \
        echo "AMP 3 beta currently supports linux/amd64 only (got ${TARGETPLATFORM:-unknown})." >&2; \
        exit 1; \
    fi

# systemd is required by AMP 3 native shard launches. The remaining
# packages support common game server runtimes hosted inside this container.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    dbus \
    iproute2 \
    jq \
    locales \
    nftables \
    sed \
    systemd \
    systemd-sysv \
    tzdata \
    wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Mono is still required by some AMP game applications.
RUN apt-get update && \
    apt-get install -y --no-install-recommends mono-devel && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Native dependencies used by common game server applications.
ARG AMPDEPS="\
    bzip2 \
    coreutils \
    gdb \
    git \
    git-lfs \
    iputils-ping \
    libc++-dev \
    libc6 \
    libatomic1 \
    libgdiplus \
    liblua5.3-0 \
    libpulse-dev \
    libsqlite3-0 \
    libzstd1 \
    numactl \
    procps \
    socat \
    tmux \
    unzip \
    xz-utils \
    libicu76"

ARG SRCDSDEPS="\
    lib32gcc-s1 \
    lib32stdc++6 \
    lib32z1 \
    libbz2-1.0:i386 \
    libcurl3t64-gnutls:i386 \
    libcurl4t64 \
    libncurses6:i386 \
    libsdl2-2.0-0 \
    libsdl2-2.0-0:i386 \
    libtinfo6:i386"

ARG WINEXVFB="\
    fonts-wine \
    libwine \
    libwine:i386 \
    python3 \
    python3-venv \
    cabextract \
    wine \
    wine32 \
    wine64 \
    wine-binfmt \
    winbind \
    xauth \
    xvfb"

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends $AMPDEPS $SRCDSDEPS $WINEXVFB && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Adoptium JDKs commonly used by AMP game applications.
RUN wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | tee /etc/apt/keyrings/adoptium.asc && \
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends temurin-8-jdk temurin-11-jdk temurin-17-jdk temurin-21-jdk temurin-25-jdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Temurin packages register Java alternatives themselves.
ENV JAVA_HOME=/usr/lib/jvm/temurin-25-jdk-amd64

COPY entrypoint/ /opt/entrypoint/
ARG AMP3_PACKAGE_CACHE_BUST=manual
# Download signed packages and extract their payloads, as the AMP 2 image does.
# Data initialization is handled by this image, not the package post-installs.
RUN printf '%s\n' "$AMP3_PACKAGE_CACHE_BUST" && \
    bash /opt/entrypoint/install-packages.sh && \
    groupadd --system amp && \
    useradd --system --gid amp --home-dir /opt/cubecoders/amp3/data --shell /usr/sbin/nologin amp && \
    install -d -m 0700 /etc/wireguard && \
    install -d -m 0755 /etc/caddy && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# AMP's built-in traversal fallback supports Unraid FUSE, where ACLs can be
# recorded without granting access. Keep setfacl out of the runtime image.
RUN ! command -v setfacl

COPY entrypoint/amp3-bootstrap.service /etc/systemd/system/amp3-bootstrap.service
RUN chmod 0755 /opt/entrypoint/main.sh && \
    mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -s /etc/systemd/system/amp3-bootstrap.service /etc/systemd/system/multi-user.target.wants/amp3-bootstrap.service && \
    for unit in amp3 amp3-bus amp3-sysagent; do \
      mkdir -p "/etc/systemd/system/$unit.service.d"; \
      printf '[Unit]\nRequires=amp3-bootstrap.service\nAfter=amp3-bootstrap.service\n\n[Service]\nStandardOutput=journal+console\nStandardError=journal+console\n' >"/etc/systemd/system/$unit.service.d/container.conf"; \
      ln -s "/usr/lib/systemd/system/$unit.service" "/etc/systemd/system/multi-user.target.wants/$unit.service"; \
    done && \
    systemctl mask apt-daily.timer apt-daily-upgrade.timer console-getty.service && \
    systemctl set-default multi-user.target && \
    truncate -s 0 /etc/machine-id && \
    rm -f /var/lib/dbus/machine-id

EXPOSE 8443/tcp
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/opt/entrypoint/main.sh"]
