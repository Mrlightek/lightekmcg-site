FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       asterisk freeradius freeradius-utils openssl sip-tester \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lightek-communications
COPY run.sh pjsip.conf extensions.conf echo.xml radius-site ./
CMD ["/bin/sh", "./run.sh", "--isolated-container"]
