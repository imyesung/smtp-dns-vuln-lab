#!/bin/bash
# scripts/capture_smtp.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}"
fi

LOG_DIR="/artifacts"
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
LOG_FILE="${LOG_DIR}/tcpdump_${ATTACK_ID}.log"

mkdir -p "$LOG_DIR"
safe_logfile "$LOG_FILE"

echo "=== SMTP 패킷 캡처 시작 (포트 25, 587, 465) ===" | tee -a "$LOG_FILE"
echo "시작 시간: $(iso8601_now)" | tee -a "$LOG_FILE"

# 네트워크 상황 출력
echo "라우팅 테이블:" | tee -a "$LOG_FILE"
ip route show | tee -a "$LOG_FILE"

echo "네트워크 인터페이스:" | tee -a "$LOG_FILE"
ip link show | tee -a "$LOG_FILE"

# 캡처 인터페이스 간단화 (eth0 우선)
CAPTURE_INTERFACE="any"
echo "캡처 인터페이스: $CAPTURE_INTERFACE" | tee -a "$LOG_FILE"

# 포트 25, 587, 465 모두 캡처
FILTER="port 25 or port 587 or port 465"
TCPDUMP_OPTS="-i $CAPTURE_INTERFACE -nn -v"
echo "TCPDUMP 옵션: $TCPDUMP_OPTS / 필터: $FILTER (오픈릴레이 + MSA 포트)" | tee -a "$LOG_FILE"

# 기존 PCAP 제거
if [ -f "$PCAP_FILE" ]; then
    rm "$PCAP_FILE"
    echo "기존 PCAP 제거: $PCAP_FILE" | tee -a "$LOG_FILE"
fi

# Postfix 컨테이너 내부에서도 /artifacts 폴더 확인/생성
docker exec mail-postfix sh -c "mkdir -p /artifacts && touch '$PCAP_FILE'"

TCPDUMP_PID_FILE_IN_MAIL_POSTFIX="/artifacts/tcpdump_${ATTACK_ID}.pid"
DOCKER_EXEC_LOG_FILE="${LOG_DIR}/docker_exec_mail_postfix_${ATTACK_ID}.log"

echo "$(iso8601_now) Starting dual-port tcpdump in mail-postfix for $ATTACK_ID. Docker exec log: $DOCKER_EXEC_LOG_FILE" | tee -a "$LOG_FILE"

# mail-postfix 컨테이너 내에서 tcpdump를 백그라운드로 실행하고, 그 PID를 파일에 저장
docker exec mail-postfix sh -c \
  "tcpdump -i any -nn -v '$FILTER' -w '$PCAP_FILE' 2>> '${LOG_DIR}/tcpdump_stderr_in_container_${ATTACK_ID}.log' & echo \$! > '$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX'; exit_code=\$?; echo \"PID file write attempt. Exit code: \$exit_code. PID: \$(cat '$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX' 2>/dev/null)\" " >> "$DOCKER_EXEC_LOG_FILE" 2>&1

# PID 파일이 생성될 때까지 잠시 대기 후 PID 읽기
sleep 2 
ACTUAL_TCPDUMP_PID=$(docker exec mail-postfix cat "$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX" 2>/dev/null | tr -d '[:space:]')

if [[ -n "$ACTUAL_TCPDUMP_PID" && "$ACTUAL_TCPDUMP_PID" -gt 0 ]]; then
    echo "tcpdump started in mail-postfix with PID $ACTUAL_TCPDUMP_PID (capturing ports 25,587,465). PID saved in $TCPDUMP_PID_FILE_IN_MAIL_POSTFIX" | tee -a "$LOG_FILE"
    echo "$ACTUAL_TCPDUMP_PID" > "/tmp/tcpdump_actual_pid_${ATTACK_ID}.txt"
else
    echo "ERROR: Failed to get actual tcpdump PID from mail-postfix." | tee -a "$LOG_FILE"
    exit 1
fi

touch /artifacts/capture_started_before

ARTIFACTS_DIR="/artifacts"

exit 0