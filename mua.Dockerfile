FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    swaks \
    telnet \
    openssl \
    dnsutils \
    netcat-openbsd \
    curl \
    python3 \
    python3-pip \
    bash \
    vim \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /scripts

ENTRYPOINT ["/bin/bash"]
