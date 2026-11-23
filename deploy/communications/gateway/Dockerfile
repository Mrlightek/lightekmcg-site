FROM ubuntu:24.04 AS network-tools
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       iproute2 iputils-ping ppp pppoe \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/lightek-gateway
COPY subscriber.sh ./

FROM network-tools AS gateway
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       freeradius freeradius-utils nftables openssl \
    && rm -rf /var/lib/apt/lists/*
COPY gateway.sh access-policy.sh radius-site radius-access radiusclient.conf radius-dictionary ppp-options forward.nft ./
CMD ["/bin/sh", "./gateway.sh"]
