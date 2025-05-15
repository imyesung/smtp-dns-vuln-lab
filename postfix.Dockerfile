FROM debian:bullseye-slim

# 필요한 패키지 설치 (postfix, tcpdump 및 문제 분석용 도구)
RUN apt-get update && \
    apt-get install -y postfix tcpdump procps dnsutils net-tools bash && \
    # Postfix 패키지 설치 후 필요한 디렉토리 생성 및 권한 설정 보장
    # Postfix 패키지가 이를 수행해야 하지만, 문제가 발생하는 경우를 대비한 명시적 조치입니다.
    mkdir -p /var/spool/postfix && \
    chown postfix:postdrop /var/spool/postfix && \
    # Postfix 큐 디렉토리 아래에는 여러 하위 디렉토리가 필요하며,
    # 'postfix check' 또는 Postfix 시작 시 생성될 수 있지만,
    # /var/spool/postfix 디렉토리 자체의 존재와 기본 권한이 중요합니다.
    # 더 확실하게 하려면 Postfix의 set-permissions 스크립트를 실행하거나
    # 주요 하위 디렉토리(incoming, active, deferred, private, public 등)를 만들고 권한을 설정할 수 있습니다.
    # 예: mkdir -p /var/spool/postfix/public /var/spool/postfix/private 등
    rm -rf /var/lib/apt/lists/*

# 시작 스크립트 생성 - 포스트픽스를 시작하고 컨테이너를 계속 실행 상태로 유지
RUN echo '#!/bin/bash\n\
echo "Starting Postfix..."\n\
# Postfix 시작 전 postfix check 실행 (추가적인 오류 확인 또는 권한 수정에 도움될 수 있음)\n\
# postfix check\n\
/etc/init.d/postfix start\n\
echo "Postfix started, keeping container alive..."\n\
# Postfix 상태 확인 (선택 사항)\n\
# /etc/init.d/postfix status\n\
# 시작 실패 시 로그 출력 (선택 사항)\n\
# if [ \$? -ne 0 ]; then cat /var/log/postfix.log || cat /var/log/mail.log; fi\n\
tail -f /dev/null' > /start.sh && \
chmod +x /start.sh

# 설정 파일은 volume으로 마운트되므로 COPY 불필요
# COPY configs/postfix /etc/postfix

CMD ["/start.sh"]