#!/bin/bash
# 표준화된 실험 워크플로우 스크립트 - Enhanced with common utilities

# 공통 함수 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# 공통 초기화
init_common
SCRIPT_START_TIME=$(date +%s)

# 인자 처리 (backward compatibility 유지)
PHASE=$1
if [[ -z "$PHASE" ]]; then
    log_error "Usage: $0 [before|after] [attack_id]"
    log_info "Examples:"
    log_info "  $0 before"
    log_info "  $0 after EXP_20250610_120000"
    exit 1
fi

# Attack ID 처리
ATTACK_ID="${2:-$(generate_attack_id "ORT")}-${PHASE}"

log_info "Starting standardized experiment workflow"
log_info "Phase: $PHASE"
log_info "Attack ID: $ATTACK_ID"

# 필수 명령어 확인
check_required_commands docker || exit 1

# 설정 변수
LOG_DIR="/artifacts"
ensure_directory "$LOG_DIR"

# 파일 경로 정의
PCAP_FILE="${LOG_DIR}/smtp_${ATTACK_ID}.pcap"
ATTACK_LOG="${LOG_DIR}/openrelay_${ATTACK_ID}.log"
ANALYSIS_FILE="${LOG_DIR}/analysis_${ATTACK_ID}.txt"
log_warn()  { echo -e "${YELLOW}[$(date +"%H:%M:%S")] [WARN] $1${NC}"; }
log_error() { echo -e "${RED}[$(date +"%H:%M:%S")] [ERROR] $1${NC}"; }

# 스크립트 존재 확인
for script in ./capture_smtp.sh ./attack_openrelay.sh ./analyze_pcap.sh; do
    if [[ ! -x "$script" ]]; then
        log_error "$script 스크립트를 찾을 수 없거나 실행 권한이 없습니다."
        exit 1
    fi
done

log_info "===== SMTP 오픈 릴레이 테스트 ($PHASE) 시작 ====="
log_info "실험 ID: $ATTACK_ID"
log_info "로그 디렉토리: $LOG_DIR"
log_info "패킷 캡처 파일: $PCAP_FILE"
log_info "공격 로그 파일: $ATTACK_LOG"

# 1단계: 캡처 시작
log_step "1. SMTP 트래픽 캡처 시작"
./capture_smtp.sh "$ATTACK_ID" &
CAPTURE_PID=$!
sleep 3

if ! kill -0 $CAPTURE_PID 2>/dev/null; then
    log_error "캡처 프로세스가 시작되지 않았습니다."
    exit 2
fi
log_info "캡처 PID: $CAPTURE_PID"

# 2단계: 공격 실행
log_step "2. 오픈 릴레이 테스트 실행"
./attack_openrelay.sh "$ATTACK_ID"
ATTACK_STATUS=$?
[[ $ATTACK_STATUS -ne 0 ]] && log_warn "오픈 릴레이 테스트 비정상 종료" || log_info "오픈 릴레이 테스트 완료"

# 3단계: 추가 캡처 및 중지
log_step "3. 30초 추가 캡처 후 중지"
sleep 30
kill $CAPTURE_PID 2>/dev/null
wait $CAPTURE_PID 2>/dev/null
log_info "캡처 종료 완료"

# 4단계: PCAP 분석
log_step "4. 패킷 분석 시작"
[[ ! -f "$PCAP_FILE" ]] && log_error "캡처 파일이 존재하지 않음: $PCAP_FILE" && exit 3
./analyze_pcap.sh "$PCAP_FILE" "$ANALYSIS_FILE"
[[ $? -ne 0 ]] && log_error "PCAP 분석 실패" && exit 4

# 5단계: 결과 요약
log_step "5. 결과 요약"
log_info "PCAP: $PCAP_FILE"
log_info "로그: $ATTACK_LOG"
log_info "분석: $ANALYSIS_FILE"

# 주요 통계 출력
if [[ -f "$ANALYSIS_FILE" ]]; then
    SMTP_CMDS=$(grep -A 10 "SMTP 명령어 통계" "$ANALYSIS_FILE" | grep -v "SMTP 명령어 통계" | grep -v "\`\`\`" | grep -v "^$" | head -n 5)
    log_info "주요 SMTP 명령어 통계:"
    echo "$SMTP_CMDS"

    if grep -q "MAIL FROM" "$ANALYSIS_FILE" && grep -q "RCPT TO" "$ANALYSIS_FILE" && grep -q "DATA" "$ANALYSIS_FILE"; then
        if grep -q "250 2.0.0 Ok:" "$ANALYSIS_FILE"; then
            log_warn "오픈 릴레이 감지됨 - 메일 전송 성공 추정"
        else
            log_info "메일 전송 시도는 있었으나 성공 여부 불확실"
        fi
    else
        log_info "완전한 SMTP 세션이 감지되지 않음"
    fi
fi

log_info "===== 실험 완료 ($PHASE) ====="
log_info "결과 저장 위치: $LOG_DIR"
log_info "상세 분석: $ANALYSIS_FILE"
exit 0