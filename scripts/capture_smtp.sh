#!/bin/bash
# SMTP 패킷 캡처 스크립트 - Enhanced with common utilities

# 공통 함수 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 공통 초기화
init_common
SCRIPT_START_TIME=$(date +%s)

# 인자 처리
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    ATTACK_ID=$(generate_attack_id "ORT")
fi

log_info "Starting SMTP packet capture - ID: $ATTACK_ID"

# 필수 명령어 확인
check_required_commands tcpdump docker || exit 1

# 로그 및 파일 설정
LOG_DIR="/artifacts"
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
LOG_FILE="${LOG_DIR}/tcpdump_${ATTACK_ID}.log"

ensure_directory "$LOG_DIR"
safe_logfile "$LOG_FILE"

log_step "=== SMTP 패킷 캡처 시작 ==="
log_info "시작 시간: $(iso8601_now)"

# 네트워크 상황 출력
echo "라우팅 테이블:" | tee -a "$LOG_FILE"
ip route show | tee -a "$LOG_FILE"

echo "네트워크 인터페이스:" | tee -a "$LOG_FILE"
ip link show | tee -a "$LOG_FILE"

# 캡처 인터페이스 간단화 (eth0 우선)
CAPTURE_INTERFACE="any"
echo "캡처 인터페이스: $CAPTURE_INTERFACE" | tee -a "$LOG_FILE"

FILTER="port 25 or port 587 or port 465"
TCPDUMP_OPTS="-i $CAPTURE_INTERFACE -nn -v"
echo "TCPDUMP 옵션: $TCPDUMP_OPTS / 필터: $FILTER" | tee -a "$LOG_FILE"

# 기존 PCAP 제거
if [ -f "$PCAP_FILE" ]; then
    rm "$PCAP_FILE"
    echo "기존 PCAP 제거: $PCAP_FILE" | tee -a "$LOG_FILE"
fi

# Postfix 컨테이너 내부에서도 /artifacts 폴더 확인/생성
docker exec mail-postfix sh -c "mkdir -p /artifacts && touch '$PCAP_FILE'"

TCPDUMP_PID_FILE_IN_MAIL_POSTFIX="/artifacts/tcpdump_${ATTACK_ID}.pid"
# mail-postfix 컨테이너 내에서 tcpdump 실행 시 발생하는 모든 출력을 로그 파일에 기록
DOCKER_EXEC_LOG_FILE="${LOG_DIR}/docker_exec_mail_postfix_${ATTACK_ID}.log"

echo "$(iso8601_now) Starting tcpdump in mail-postfix for $ATTACK_ID. Docker exec log: $DOCKER_EXEC_LOG_FILE" | tee -a "$LOG_FILE"

# mail-postfix 컨테이너 내에서 tcpdump를 백그라운드로 실행하고, 그 PID를 파일에 저장
# 표준 출력과 표준 에러를 모두 DOCKER_EXEC_LOG_FILE로 리디렉션
docker exec mail-postfix sh -c \
  "tcpdump -i any -nn -v '$FILTER' -w '$PCAP_FILE' 2>> '${LOG_DIR}/tcpdump_stderr_in_container_${ATTACK_ID}.log' & echo \$! > '$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX'; wait" >> "$DOCKER_EXEC_LOG_FILE" 2>&1 &

# Docker 백그라운드 프로세스 PID 저장
DOCKER_EXEC_PID=$!
echo "$DOCKER_EXEC_PID" > "/tmp/docker_exec_pid_${ATTACK_ID}.txt"

# PID 파일이 생성될 때까지 대기
log_info "Waiting for tcpdump to start..."
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 10 ]; do
    if docker exec mail-postfix test -f "$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX"; then
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

ACTUAL_TCPDUMP_PID=$(docker exec mail-postfix cat "$TCPDUMP_PID_FILE_IN_MAIL_POSTFIX" 2>/dev/null | tr -d '[:space:]')

if [[ -n "$ACTUAL_TCPDUMP_PID" && "$ACTUAL_TCPDUMP_PID" -gt 0 ]]; then
    echo "tcpdump started in mail-postfix with PID $ACTUAL_TCPDUMP_PID. PID saved in $TCPDUMP_PID_FILE_IN_MAIL_POSTFIX" | tee -a "$LOG_FILE"
    echo "$ACTUAL_TCPDUMP_PID" > "/tmp/tcpdump_actual_pid_${ATTACK_ID}.txt"
    
    # 캡처 시작 완료 신호 파일 생성
    touch "/artifacts/capture_started_${ATTACK_ID}"
    log_info "Packet capture started successfully"
else
    log_error "Failed to get actual tcpdump PID from mail-postfix."
    exit 1
fi
exit 0