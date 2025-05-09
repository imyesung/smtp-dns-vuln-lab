FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    iputils-ping \
    netcat \
    swaks \
    curl \
    bash \
    && apt-get clean

WORKDIR /scripts
ENTRYPOINT ["/bin/bash"]
