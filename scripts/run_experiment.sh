#!/bin/bash
# run_experiment.sh - SMTP 오픈 릴레이 테스트 자동화 스크립트

# 색상 정의 (로그 가독성 향상)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정 변수
LOG_DIR="/artifacts"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ATTACK_ID="ORT-${TIMESTAMP}"
mkdir -p "$LOG_DIR"

# 함수: 단계별 로그 출력
log_step() {
    echo -e "${GREEN}[$(date +"%H:%M:%S")] [STEP] $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date +"%H:%M:%S")] [INFO] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +"%H:%M:%S")] [WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +"%H:%M:%S")] [ERROR] $1${NC}"
}

# 스크립트 존재 확인
if [[ ! -x "./capture_smtp.sh" ]]; then
    log_error "capture_smtp.sh 스크립트를 찾을 수 없거나 실행 권한이 없습니다."
    exit 1
fi

if [[ ! -x "./attack_openrelay.sh" ]]; then
    log_error "attack_openrelay.sh 스크립트를 찾을 수 없거나 실행 권한이 없습니다."
    exit 1
fi

if [[ ! -x "./analyze_pcap.sh" ]]; then
    log_error "analyze_pcap.sh 스크립트를 찾을 수 없거나 실행 권한이 없습니다."
    exit 1
fi

# 실험 시작 안내
log_info "===== SMTP 오픈 릴레이 테스트 실험 시작 ====="
log_info "실험 ID: $ATTACK_ID"
log_info "로그 디렉토리: $LOG_DIR"

# 파일 경로 미리 정의 (일관성 확보)
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
ATTACK_LOG="${LOG_DIR}/openrelay_${ATTACK_ID}.log"
ANALYSIS_FILE="${LOG_DIR}/analysis_${ATTACK_ID}.txt"

log_info "패킷 캡처 파일: $PCAP_FILE"
log_info "공격 로그 파일: $ATTACK_LOG"

# 1단계: 캡처 시작 (백그라운드)
log_step "1. SMTP 트래픽 캡처 시작"
./capture_smtp.sh "$ATTACK_ID" &
CAPTURE_PID=$!

# 캡처가 시작될 때까지 대기
sleep 3
# ps 명령어 대신 kill -0 사용하여 프로세스 존재 확인
if ! kill -0 $CAPTURE_PID 2>/dev/null; then
    log_error "캡처 프로세스가 정상적으로 시작되지 않았습니다."
    exit 2
fi
log_info "캡처 프로세스 PID: $CAPTURE_PID"

# 캡처 파일 생성 확인
for i in {1..5}; do
    if [[ -f "$PCAP_FILE" ]] || [[ -f "${PCAP_FILE}.temp" ]]; then
        log_info "패킷 캡처 파일이 생성되었습니다."
        break
    fi
    
    if [[ $i -eq 5 ]]; then
        log_warn "패킷 캡처 파일이 아직 생성되지 않았습니다. 계속 진행합니다."
    else
        log_info "패킷 캡처 파일 생성 대기 중... ($i/5)"
        sleep 1
    fi
done

# 2단계: 공격 실행
log_step "2. 오픈 릴레이 테스트 실행"
./attack_openrelay.sh "$ATTACK_ID"
ATTACK_STATUS=$?

if [ $ATTACK_STATUS -ne 0 ]; then
    log_warn "오픈 릴레이 테스트가 비정상 종료되었습니다 (종료 코드: $ATTACK_STATUS)"
else
    log_info "오픈 릴레이 테스트 완료"
fi

# 3단계: 캡처 중지
log_step "3. SMTP 트래픽 캡처 중지"
# 30초 더 기다려 후속 트래픽도 캡처
log_info "추가 트래픽 확인을 위해 30초 더 캡처합니다..."
sleep 30

# 캡처 프로세스 종료
kill $CAPTURE_PID 2>/dev/null
wait $CAPTURE_PID 2>/dev/null
log_info "캡처 프로세스 종료됨"

# 4단계: PCAP 분석
log_step "4. 캡처된 패킷 분석"

if [[ ! -f "$PCAP_FILE" ]]; then
    log_error "캡처 파일이 생성되지 않았습니다: $PCAP_FILE"
    exit 3
fi

log_info "PCAP 파일 분석 중: $PCAP_FILE"
./analyze_pcap.sh "$PCAP_FILE" "$ANALYSIS_FILE"

if [[ $? -ne 0 ]]; then
    log_error "PCAP 분석 중 오류가 발생했습니다."
    exit 4
fi

# 5단계: 결과 요약
log_step "5. 실험 결과 요약"
log_info "실험 ID: $ATTACK_ID"
log_info "PCAP 파일: $PCAP_FILE"
log_info "분석 결과: $ANALYSIS_FILE"

# 간단한 결과 요약 표시
if [[ -f "$ANALYSIS_FILE" ]]; then
    SMTP_CMDS=$(grep -A 10 "SMTP 명령어 통계" "$ANALYSIS_FILE" | grep -v "SMTP 명령어 통계" | grep -v "\`\`\`" | grep -v "^$" | head -n 5)
    
    log_info "주요 SMTP 명령어 통계:"
    echo "$SMTP_CMDS"
    
    # 결과 해석 (기본적인 판단)
    if grep -q "MAIL FROM" "$ANALYSIS_FILE" && grep -q "RCPT TO" "$ANALYSIS_FILE" && grep -q "DATA" "$ANALYSIS_FILE"; then
        if grep -q "250 2.0.0 Ok:" "$ANALYSIS_FILE"; then
            log_warn "오픈 릴레이 가능성이 감지되었습니다 - 메일 전송이 성공한 것으로 보입니다."
        else
            log_info "메일 전송 시도는 있었으나, 성공 여부는 불확실합니다."
        fi
    else
        log_info "완전한 SMTP 세션이 감지되지 않았습니다."
    fi
fi

log_info "===== 실험 완료 ====="
log_info "모든 결과는 $LOG_DIR 디렉토리에 저장되었습니다."
log_info "상세 분석은 $ANALYSIS_FILE 파일을 확인하세요."

exit 0