#!/bin/bash
# scripts/capture_smtp.sh

# utils.sh 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}"
fi

# 설정 변수
LOG_DIR="/artifacts"
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
LOG_FILE="${LOG_DIR}/tcpdump_${ATTACK_ID}.log"

mkdir -p "$LOG_DIR"

# 기존 로그 파일 백업 (utils.sh 함수 활용)
safe_logfile "$LOG_FILE"

echo "=== 프로덕션급 SMTP 패킷 캡처 시작 ===" | tee -a "$LOG_FILE"
echo "시작 시간: $(iso8601_now)" | tee -a "$LOG_FILE"

# 1. 네트워크 토폴로지 분석
echo "=== 네트워크 토폴로지 분석 ===" | tee -a "$LOG_FILE"
echo "라우팅 테이블:" | tee -a "$LOG_FILE"
ip route show | tee -a "$LOG_FILE"
echo "ARP 테이블:" | tee -a "$LOG_FILE"
arp -a 2>/dev/null | tee -a "$LOG_FILE" || echo "ARP 정보 없음" | tee -a "$LOG_FILE"

# 2. 네트워크 인터페이스 스마트 감지
echo "=== 네트워크 인터페이스 분석 ===" | tee -a "$LOG_FILE"
ACTIVE_INTERFACES=($(ip link show up | awk -F: '$0 !~ "lo|docker0"{print $2}' | tr -d ' ' | grep -v '^$'))
echo "활성 인터페이스: ${ACTIVE_INTERFACES[@]}" | tee -a "$LOG_FILE"

# Docker 브리지 네트워크 자동 감지
DOCKER_BRIDGES=($(ip link show | grep -E 'br-[a-f0-9]{12}|docker[0-9]' | awk -F: '{print $2}' | tr -d ' '))
if [ ${#DOCKER_BRIDGES[@]} -gt 0 ]; then
    CAPTURE_INTERFACE="${DOCKER_BRIDGES[0]}"
    echo "Docker 브리지 감지: $CAPTURE_INTERFACE" | tee -a "$LOG_FILE"
else
    # 모든 인터페이스에서 캡처
    CAPTURE_INTERFACE="any"
    echo "브리지 인터페이스 없음. any 인터페이스 사용" | tee -a "$LOG_FILE"
fi

# 3. 보안 분석용 필터
FILTER="port 25"
echo "보안 분석 필터: $FILTER" | tee -a "$LOG_FILE"

# 4. 캡처 옵션
TCPDUMP_OPTS="-i $CAPTURE_INTERFACE -nn -v"
echo "캡처 옵션: $TCPDUMP_OPTS" | tee -a "$LOG_FILE"

# 5. 기존 PCAP 파일 제거
if [ -f "$PCAP_FILE" ]; then
    rm "$PCAP_FILE"
    echo "기존 PCAP 파일 제거: $PCAP_FILE" | tee -a "$LOG_FILE"
fi

# 6. 캡처 시작 (백그라운드)
echo "$(iso8601_now) 패킷 캡처 시작" | tee -a "$LOG_FILE"
echo "명령어: tcpdump $TCPDUMP_OPTS \"$FILTER\" -w \"$PCAP_FILE\"" | tee -a "$LOG_FILE"

# tcpdump 실행 및 PID 저장
tcpdump $TCPDUMP_OPTS "$FILTER" -w "$PCAP_FILE" &
TCPDUMP_PID=$!

# PID 파일에 저장 (종료 시 사용)
echo $TCPDUMP_PID > /tmp/tcpdump_${ATTACK_ID}.pid
echo "tcpdump PID: $TCPDUMP_PID (saved to /tmp/tcpdump_${ATTACK_ID}.pid)" | tee -a "$LOG_FILE"

# 프로세스 확인
sleep 3
if kill -0 $TCPDUMP_PID 2>/dev/null; then
    echo "캡처 프로세스 정상 시작됨 (PID: $TCPDUMP_PID)" | tee -a "$LOG_FILE"
    
    # 프로세스 상세 정보
    echo "프로세스 정보:" | tee -a "$LOG_FILE"
    ps aux | grep $TCPDUMP_PID | grep -v grep | tee -a "$LOG_FILE"
else
    echo "ERROR: 캡처 프로세스 시작 실패" | tee -a "$LOG_FILE"
    echo "tcpdump 오류 로그 확인:" | tee -a "$LOG_FILE"
    tail -10 "$LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# 캡처 시작 신호 생성
touch "${LOG_DIR}/capture_started"
echo "캡처 시작 신호 생성: ${LOG_DIR}/capture_started" | tee -a "$LOG_FILE"

# 7. 백그라운드에서 실행 계속
echo "$(iso8601_now) 캡처 백그라운드 실행 중..." | tee -a "$LOG_FILE"
echo "종료하려면: kill $TCPDUMP_PID" | tee -a "$LOG_FILE"

# 스크립트는 종료되지만 tcpdump는 백그라운드에서 계속 실행됨
exit 0