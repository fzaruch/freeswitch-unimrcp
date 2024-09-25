FROM ubuntu:22.04

ARG FREESWITCH_REL=1.10.12
ARG NPROC 4

RUN apt-get update && apt-get upgrade -y

RUN apt-get install --yes \
    build-essential \
    pkg-config \
    uuid-dev \
    zlib1g-dev \
    libjpeg-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libpcre3-dev \
    libspeexdsp-dev \
    libldns-dev \
    libedit-dev \
    libtiff5-dev \
    yasm \
    libopus-dev \
    libsndfile1-dev \
    unzip \
    libavformat-dev \
    libswscale-dev \
    liblua5.2-dev \
    liblua5.2-0 \
    cmake \
    libpq-dev \
    unixodbc-dev \
    autoconf \
    automake \
    ntpdate \
    libxml2-dev \
    libpq-dev \
    libpq5 \
    sngrep \
    git \
    wget \
    vim

# FREESWITCH dependencies

RUN git clone https://github.com/signalwire/libks.git /usr/local/src/libks
RUN cd /usr/local/src/libks && \
    cmake . && \
    make && \
    make -j $NPROC && \
    make install

RUN git clone https://github.com/signalwire/signalwire-c.git /usr/local/src/signalwire-c
RUN cd /usr/local/src/signalwire-c && \
    cmake . && \
    make -j $NPROC && \
   make install
   
RUN git clone https://github.com/freeswitch/sofia-sip /usr/local/src/sofia-sip
RUN cd /usr/local/src/sofia-sip && \
    ./bootstrap.sh && \
    ./configure && \
    make -j $NPROC && \
    make install

RUN git clone https://github.com/freeswitch/spandsp /usr/local/src/spandsp
RUN cd /usr/local/src/spandsp && \
    ./bootstrap.sh && \
    ./configure && \
    make -j $NPROC && \
    make install

# Unimrcp

RUN wget https://www.unimrcp.org/project/component-view/unimrcp-deps-1-6-0-tar-gz/download -O /usr/local/src/unimrcp-deps-1.6.0.tar.gz
RUN cd /usr/local/src && tar xvzf unimrcp-deps-1.6.0.tar.gz && \
    cd unimrcp-deps-1.6.0/libs/apr && \
    ./configure --prefix=/usr/local/apr && make -j $NPROC && make install && \
    cd ../apr-util/ && \
   ./configure --prefix=/usr/local/apr --with-apr=/usr/local/apr && \
   make -j  $NPROC && \
   make install

RUN cd /usr/local/src && \
    git clone https://github.com/unispeech/unimrcp.git && \
    cd unimrcp && \
    ./bootstrap && \
    ./configure && \
    make -j $NPROC && \
    make install

# Install FREESWITCH

WORKDIR /usr/local/src

# Getting release from: https://files.freeswitch.org/releases/freeswitch/
RUN wget -c https://files.freeswitch.org/releases/freeswitch/freeswitch-${FREESWITCH_REL}.-release.tar.gz -P /usr/local/src
RUN tar -zxvf freeswitch-${FREESWITCH_REL}.-release.tar.gz && rm freeswitch-${FREESWITCH_REL}.-release.tar.gz
COPY res/patch.diff /usr/local/src

# Fix errors due mod_spandsp module
# Ref.: https://github.com/signalwire/freeswitch/issues/2158
RUN cd freeswitch-${FREESWITCH_REL}.-release && \
    cat ../patch.diff | patch -p 1

WORKDIR /usr/local/src/freeswitch-${FREESWITCH_REL}.-release

RUN ./configure && \
    make -j $NPROC && \
    make install

# Build mod_unimrcp and include in FREESWITCH build
RUN cd src/mod/asr_tts && \
    git clone https://github.com/freeswitch/mod_unimrcp.git && \
    cd mod_unimrcp && \
    export PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig && \
    ./bootstrap.sh && \
    ./configure && \
    make -j $NPROC && \
    make install

# Include mod_unimrcp in FREESWITCH build
RUN echo "asr_tts/mod_unimrcp" >> modules.conf && \
    ./configure && \
    make -j $NPROC && \
    make install

RUN make cd-sounds-install && make install
RUN make cd-sounds-install && make cd-moh-install

RUN  ln -s /usr/local/freeswitch/conf /etc/freeswitch 
RUN  ln -s /usr/local/freeswitch/bin/fs_cli /usr/bin/fs_cli 
RUN  ln -s /usr/local/freeswitch/bin/freeswitch /usr/sbin/freeswitch

# copy configuration file
COPY res/unimrcp.conf.xml /etc/freeswitch/autoload_configs/unimrcp.conf.xml
RUN mkdir -p /etc/freeswitch/mrcp_profiles/
COPY res/unimrcpserver-mrcp-v2.xml /etc/freeswitch/mrcp_profiles/unimrcpserver-mrcp-v2.xml
COPY res/default.xml /etc/freeswitch/dialplan/default.xml
COPY res/modules.conf.xml /etc/freeswitch/autoload_configs/modules.conf.xml

ENV LD_LIBRARY_PATH=/usr/local/lib/

ENTRYPOINT /usr/local/freeswitch/bin/freeswitch -c -nonat

LABEL description="Freeswitch and mod_unimrcp"
LABEL version=ubuntu22.04_unimrcp_1.8_freeswitch_${FREESWITCH_REL}
