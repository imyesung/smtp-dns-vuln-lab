FROM debian:bullseye-slim

RUN apt update && apt install -y \
    iputils-ping \
    netcat \
    tcpdump \
    curl \
    swaks \
    tshark \
    bash \
    && apt clean

WORKDIR /scripts
ENTRYPOINT ["/bin/bash"]