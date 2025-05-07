FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y swaks && \
    apt-get clean

CMD ["tail", "-f", "/dev/null"]
