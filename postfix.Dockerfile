FROM debian:bullseye-slim

# 필요한 패키지 설치 (postfix, tcpdump 및 문제 분석용 도구)
RUN apt-get update && \
    apt-get install -y postfix tcpdump procps dnsutils net-tools bash && \
    rm -rf /var/lib/apt/lists/*

# 시작 스크립트 생성 - 포스트픽스를 시작하고 컨테이너를 계속 실행 상태로 유지
RUN echo '#!/bin/bash\n\
echo "Starting Postfix..."\n\
/etc/init.d/postfix start\n\
echo "Postfix started, keeping container alive..."\n\
tail -f /dev/null' > /start.sh && \
chmod +x /start.sh

# 설정 파일은 volume으로 마운트되므로 COPY 불필요
# COPY configs/postfix /etc/postfix

CMD ["/start.sh"]