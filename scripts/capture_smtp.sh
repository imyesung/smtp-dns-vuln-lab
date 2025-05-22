#!/bin/bash

# 인자로 ATTACK_ID 받기
ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="ORT-${TIMESTAMP}"  # attack_openrelay.sh와 동일한 식별자 형식
fi

# 설정 변수
# Docker 환경에서 SMTP 트래픽 캡처를 위해 브리지 네트워크 인터페이스 사용
# INTERFACE="any" -> eth0 또는 자동 감지
PRIMARY_INTERFACE="eth0"
FALLBACK_INTERFACE="any" # 기본 인터페이스 감지 실패 시 대체 인터페이스
TARGET="mail-postfix"
PORT=25
LOG_DIR="/artifacts"  # 로그 파일 및 capture_started 플래그에 사용
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap" # 명시적으로 LOG_DIR 사용
LOG_FILE="${LOG_DIR}/tcpdump_${ATTACK_ID}.log"

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 네트워크 인터페이스 자동 감지
detect_network_interface() {
    # primary 인터페이스 확인 
    if ip link show "$PRIMARY_INTERFACE" &>/dev/null; then
        echo "$PRIMARY_INTERFACE"
        return 0
    fi
    
    # 대체 인터페이스 목록에서 첫 번째 활성 인터페이스 찾기
    local interfaces=($(ip -o link show | grep -v ' lo:' | awk -F': ' '{print $2}'))
    for iface in "${interfaces[@]}"; do
        if [[ "$iface" != "lo" ]] && ip link show "$iface" | grep -q "UP"; then
            echo "$iface"
            return 0
        fi
    done
    
    # 여전히 찾지 못하면 fallback 사용
    echo "$FALLBACK_INTERFACE"
    return 1
}

# 인터페이스 감지 및 설정
INTERFACE=$(detect_network_interface)
echo "감지된 네트워크 인터페이스: $INTERFACE" | tee -a "$LOG_FILE"

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
    "pcap_file": "$PCAP_FILE",
    "container": "controller"
}
EOF
)
echo "$START_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"

# 포트 필터만 사용하도록 변경 (호스트 필터 제거)
FILTER="port 25 or port 465 or port 587"

# 실행 명령 로깅 수정
echo "실행 명령: tcpdump -i $INTERFACE -nn -s0 -vvv '$FILTER' -w $PCAP_FILE" | tee -a "$LOG_FILE"

# tcpdump 실행 (백그라운드)
tcpdump -i "$INTERFACE" -nn -s0 -vvv "$FILTER" -w "$PCAP_FILE" &
TCPDUMP_PID=$!
# Makefile에서 PID를 사용하기 위해 /tmp에 저장
echo $TCPDUMP_PID > /tmp/capture.pid 

# capture_started 플래그 파일은 LOG_DIR을 사용하여 /artifacts 내에 생성
# Makefile에서 HOST_ARTIFACTS_DIR 기준으로 이 파일을 기다림
touch "${LOG_DIR}/capture_started"
echo "캡처 시작 플래그 파일 생성: ${LOG_DIR}/capture_started (PID: $TCPDUMP_PID)" | tee -a "$LOG_FILE"
echo "캡처 PCAP 저장 위치: $PCAP_FILE" | tee -a "$LOG_FILE"

echo "패킷 캡처 시작됨 (PID: $TCPDUMP_PID, 인터페이스: $INTERFACE)" | tee -a "$LOG_FILE"
echo "ATTACK_ID: $ATTACK_ID" | tee -a "$LOG_FILE"
echo "캡처 중지하려면: kill $TCPDUMP_PID" | tee -a "$LOG_FILE"

# tcpdump 프로세스 상태 확인 및 로깅
if command -v ps >/dev/null 2>&1; then
    if ! ps -p $TCPDUMP_PID > /dev/null 2>&1; then
        echo "오류: tcpdump 프로세스가 시작되지 않았습니다." | tee -a "$LOG_FILE"
        exit 1
    fi
else
    # ps 명령어가 없는 경우, /proc 파일시스템으로 확인
    if [ ! -d "/proc/$TCPDUMP_PID" ]; then
        echo "오류: tcpdump 프로세스가 시작되지 않았습니다." | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 캡처 중지 함수 (신호 처리용)
cleanup() {
    CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    END_INFO_JSON=$(cat <<EOF
{
    "event_type": "capture_end",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
    "pcap_file": "$PCAP_FILE",
    "duration_sec": $SECONDS,
    "interface": "$INTERFACE"
}
EOF
    )
    echo "$END_INFO_JSON" | sed 's/^[[:space:]]*//' >> "$LOG_FILE"
    
    # ps 명령어 사용 가능 여부에 따라 프로세스 확인 방법 변경
    if command -v ps >/dev/null 2>&1; then
        if ps -p $TCPDUMP_PID > /dev/null 2>&1; then
            kill $TCPDUMP_PID 2>/dev/null
            wait $TCPDUMP_PID 2>/dev/null
            echo "패킷 캡처 종료됨 (PID: $TCPDUMP_PID, 파일: $PCAP_FILE)" | tee -a "$LOG_FILE"
        else
            echo "패킷 캡처 프로세스가 이미 종료됨 (PID: $TCPDUMP_PID)" | tee -a "$LOG_FILE"
        fi
    else
        # ps 명령어가 없는 경우, /proc 파일시스템으로 확인
        if [ -d "/proc/$TCPDUMP_PID" ]; then
            kill $TCPDUMP_PID 2>/dev/null
            wait $TCPDUMP_PID 2>/dev/null
            echo "패킷 캡처 종료됨 (PID: $TCPDUMP_PID, 파일: $PCAP_FILE)" | tee -a "$LOG_FILE"
        else
            echo "패킷 캡처 프로세스가 이미 종료됨 (PID: $TCPDUMP_PID)" | tee -a "$LOG_FILE"
        fi
    fi
    exit 0
}

# 신호 처리 설정
trap cleanup SIGINT SIGTERM

# 스크립트가 바로 종료되지 않도록 대기 (외부에서 kill 신호를 받을 때까지)
wait $TCPDUMP_PID