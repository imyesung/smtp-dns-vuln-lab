FROM debian:bullseye-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iproute2 iputils-ping netcat tcpdump tshark swaks curl bash procps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /scripts
ENTRYPOINT ["/bin/bash"]