#!/bin/bash

# 설정 변수
INTERFACE="eth0"  # 네트워크 인터페이스
TARGET="mail-postfix"
PORT=25
LOG_DIR="/artifacts"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ATTACK_ID="ORT-${TIMESTAMP}"  # attack_openrelay.sh와 동일한 식별자 형식
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
LOG_FILE="${LOG_DIR}/tcpdump_${ATTACK_ID}.log"

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 로그 시작 정보 (JSON 형식)
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_INFO_JSON=$(cat <<EOF
{
    "event_type": "capture_start",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
    "interface": "$INTERFACE",
    "target_host": "$TARGET",
    "target_port": $PORT,
    "pcap_file": "$PCAP_FILE"
}
EOF
)
echo "$START_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# tcpdump 실행 명령 (필터: 특정 호스트와 포트)
echo "실행 명령: tcpdump -i $INTERFACE -nn -s0 -vvv 'host $TARGET and port $PORT' -w $PCAP_FILE" | tee -a "$LOG_FILE"

# tcpdump 실행 (백그라운드)
tcpdump -i "$INTERFACE" -nn -s0 -vvv "host $TARGET and port $PORT" -w "$PCAP_FILE" 2>> "$LOG_FILE" &
TCPDUMP_PID=$!

echo "패킷 캡처 시작됨 (PID: $TCPDUMP_PID)" | tee -a "$LOG_FILE"
echo "ATTACK_ID: $ATTACK_ID" | tee -a "$LOG_FILE"
echo "캡처 중지하려면: kill $TCPDUMP_PID" | tee -a "$LOG_FILE"

# 캡처 중지 함수 (신호 처리용)
cleanup() {
    CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    END_INFO_JSON=$(cat <<EOF
{
    "event_type": "capture_end",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
    "pcap_file": "$PCAP_FILE",
    "duration_sec": $SECONDS
}
EOF
    )
    echo "$END_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"
    
    kill $TCPDUMP_PID 2>/dev/null
    wait $TCPDUMP_PID 2>/dev/null
    echo "패킷 캡처 종료됨 (PID: $TCPDUMP_PID, 파일: $PCAP_FILE)" | tee -a "$LOG_FILE"
    exit 0
}

# 신호 처리 설정
trap cleanup SIGINT SIGTERM

# 캡처 시간 제한 (예: 60초) - 선택적
echo "캡처 자동 종료 대기 중... (60초)"
sleep 60
cleanup