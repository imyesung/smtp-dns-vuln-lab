FROM debian:bullseye-slim

# 필요한 패키지 설치 (postfix, tcpdump 및 문제 분석용 도구)
RUN apt-get update && \
    apt-get install -y postfix tcpdump procps dnsutils net-tools bash && \
    # Postfix 큐 디렉토리 및 하위 디렉토리 생성 및 권한 설정
    mkdir -p /var/spool/postfix/{active,bounce,corrupt,deferred,flush,hold,incoming,maildrop,private,public,saved,trace} && \
    chown -R postfix:postdrop /var/spool/postfix && \
    chmod -R 700 /var/spool/postfix && \
    # 로그 디렉토리 및 파일 생성
    mkdir -p /var/log && \
    touch /var/log/mail.log && \
    chown postfix:adm /var/log/mail.log && \
    chmod 664 /var/log/mail.log && \
    rm -rf /var/lib/apt/lists/*

# 시작 스크립트 생성 - 포스트픽스를 시작하고 컨테이너를 계속 실행 상태로 유지
RUN echo '#!/bin/bash\n\
echo "Starting Postfix..."\n\
# 큐 디렉토리 및 권한 복구 (컨테이너 시작 시마다 보장)\n\
mkdir -p /var/spool/postfix/{active,bounce,corrupt,deferred,flush,hold,incoming,maildrop,private,public,saved,trace}\n\
chown -R postfix:postdrop /var/spool/postfix\n\
chmod -R 700 /var/spool/postfix\n\
mkdir -p /var/log\n\
touch /var/log/mail.log\n\
chown postfix:adm /var/log/mail.log\n\
chmod 664 /var/log/mail.log\n\
# artifacts 디렉토리 생성 및 권한 보장\n\
mkdir -p /artifacts\n\
chmod 777 /artifacts\n\
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