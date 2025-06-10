#!/bin/bash
# PCAP 파일에서 SMTP 명령어 추출 스크립트 - Enhanced with common utilities

# 공통 함수 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# 공통 초기화
init_common
SCRIPT_START_TIME=$(date +%s)

# 사용법 검사
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <pcap_file> [output_file]"
    log_info "Example: $0 /artifacts/smtp_ORT-20250508_123456.pcap /artifacts/analysis_ORT-20250508_123456.txt"
    exit 1
fi

log_info "Starting PCAP analysis"

# 필수 명령어 확인
check_required_commands tshark || exit 1

# 인자 처리
PCAP_FILE="$1"
OUTPUT_FILE="${2:-${PCAP_FILE%.*}_analysis.txt}"

log_info "Input PCAP: $PCAP_FILE"
log_info "Output file: $OUTPUT_FILE"

# 입력 PCAP 파일 검증
if [ ! -f "$PCAP_FILE" ]; then
    log_error "PCAP file not found: $PCAP_FILE"
    ATTACK_ID_ERR=$(basename "$PCAP_FILE" | grep -oP 'EXP_[0-9_]+' || echo "UNKNOWN_ATTACK_ID_NO_PCAP")
    cat > "$OUTPUT_FILE" <<EOF
# SMTP 패킷 분석 보고서
- 분석 시간: $(iso8601_now)
- 공격 ID: $ATTACK_ID_ERR
- 분석 파일: $PCAP_FILE
- 오류: PCAP 파일 '$PCAP_FILE'을(를) 찾을 수 없습니다. 패킷 캡처 단계에서 문제가 발생했을 수 있습니다.

## SMTP 명령 및 응답 시퀀스
\`\`\`
(파일 없음)
\`\`\`

## 메일 내용 (있는 경우)
\`\`\`
(파일 없음)
\`\`\`
EOF
    exit 1
fi

# PCAP 파일 유효성 검증
log_info "Validating PCAP file integrity..."

# 파일 크기 검증
PCAP_SIZE=$(stat -c%s "$PCAP_FILE" 2>/dev/null || stat -f%z "$PCAP_FILE" 2>/dev/null || echo "0")
if [ "$PCAP_SIZE" -eq 0 ]; then
    log_error "PCAP file is empty: $PCAP_FILE"
    ATTACK_ID_ERR=$(basename "$PCAP_FILE" | grep -oP 'EXP_[0-9_]+' || echo "UNKNOWN_ATTACK_ID_EMPTY")
    cat > "$OUTPUT_FILE" <<EOF
# SMTP 패킷 분석 보고서
- 분석 시간: $(iso8601_now)
- 공격 ID: $ATTACK_ID_ERR
- 분석 파일: $PCAP_FILE
- 오류: PCAP 파일이 비어있습니다. 패킷 캡처가 제대로 수행되지 않았을 수 있습니다.

## SMTP 명령 및 응답 시퀀스
\`\`\`
(빈 파일)
\`\`\`

## 메일 내용 (있는 경우)
\`\`\`
(빈 파일)
\`\`\`
EOF
    exit 1
fi

# tshark으로 파일 유효성 검증 (손상된 파일 감지)
log_info "Checking PCAP file validity with tshark..."
if ! tshark -r "$PCAP_FILE" -c 1 >/dev/null 2>&1; then
    log_warn "PCAP file appears to be corrupted or incomplete: $PCAP_FILE"
    ATTACK_ID_ERR=$(basename "$PCAP_FILE" | grep -oP 'EXP_[0-9_]+' || echo "UNKNOWN_ATTACK_ID_CORRUPT")
    cat > "$OUTPUT_FILE" <<EOF
# SMTP 패킷 분석 보고서
- 분석 시간: $(iso8601_now)
- 공격 ID: $ATTACK_ID_ERR
- 분석 파일: $PCAP_FILE
- 파일 크기: $PCAP_SIZE bytes
- 오류: PCAP 파일이 손상되었거나 불완전합니다. 패킷 캡처가 제대로 종료되지 않았을 수 있습니다.

## SMTP 명령 및 응답 시퀀스
\`\`\`
(손상된 파일 - 분석 불가)
\`\`\`

## 메일 내용 (있는 경우)
\`\`\`
(손상된 파일 - 분석 불가)
\`\`\`

## 권장사항
1. 패킷 캡처 프로세스가 제대로 종료되었는지 확인
2. tcpdump 프로세스를 SIGTERM으로 안전하게 종료
3. 디스크 공간 및 권한 확인
EOF
    exit 2
fi

log_info "PCAP file validation passed (size: $PCAP_SIZE bytes)"

# ATTACK_ID 추출
ATTACK_ID=$(basename "$PCAP_FILE" | grep -oP 'EXP_[0-9_]+' || echo "UNKNOWN_ATTACK_ID")

# 임시 파일 설정
TEMP_FILE="/tmp/smtp_analysis_$$.txt"

# 종료 시 임시 파일 정리
cleanup_analysis() {
    rm -f "$TEMP_FILE"
}
trap cleanup_analysis EXIT INT TERM

# 패킷 통계 수집
log_info "Gathering packet statistics..."
TOTAL_PACKETS=$(tshark -r "$PCAP_FILE" -q -z io,stat,0 2>/dev/null | grep -E "^\|.*\|.*\|.*\|$" | tail -1 | awk -F'|' '{gsub(/[ \t]/, "", $3); print $3}' 2>/dev/null || echo "0")
SMTP_PACKETS=$(tshark -r "$PCAP_FILE" -Y "tcp.port==25 or tcp.port==587 or tcp.port==465" 2>/dev/null | wc -l || echo "0")

# SMTP 트래픽 추출
log_info "Extracting SMTP traffic..."
tshark -r "$PCAP_FILE" -Y "tcp.port==25 or tcp.port==587 or tcp.port==465" -T fields -e frame.time -e ip.src -e ip.dst -e tcp.srcport -e tcp.dstport -e tcp.payload 2>/dev/null > "$TEMP_FILE" || {
    log_warn "Failed to extract SMTP traffic, creating empty analysis"
    touch "$TEMP_FILE"
}

# 메일 내용 추출 시도
log_info "Attempting to extract mail content..."
MAIL_CONTENT=""
if [ -s "$TEMP_FILE" ]; then
    MAIL_CONTENT=$(tshark -r "$PCAP_FILE" -Y "smtp" -T fields -e smtp.req.command -e smtp.response.code -e smtp.response.parameter 2>/dev/null | head -20 || echo "")
fi

# SMTP 명령어 시퀀스 추출 (개선된 버전)
SMTP_COMMANDS=$(tshark -r "$PCAP_FILE" -Y "smtp.req.command" -T fields -e smtp.req.command -e smtp.req.parameter 2>/dev/null | head -20 || echo "")
SMTP_RESPONSES=$(tshark -r "$PCAP_FILE" -Y "smtp.response" -T fields -e smtp.response.code 2>/dev/null | head -20 || echo "")

# SMTP 응답 코드 상세 분석
RESPONSE_2XX=$(echo "$SMTP_RESPONSES" | grep -c "^2[0-9][0-9]" 2>/dev/null || echo "0")
RESPONSE_4XX=$(echo "$SMTP_RESPONSES" | grep -c "^4[0-9][0-9]" 2>/dev/null || echo "0")
RESPONSE_5XX=$(echo "$SMTP_RESPONSES" | grep -c "^5[0-9][0-9]" 2>/dev/null || echo "0")

# 보안 관련 응답 분석
RELAY_DENIALS=$(echo "$SMTP_RESPONSES" | grep -c "554\|550" 2>/dev/null || echo "0")
AUTH_FAILURES=$(tshark -r "$PCAP_FILE" -Y "smtp" -T fields -e smtp.response.parameter 2>/dev/null | grep -ci "authentication\|access denied" || echo "0")

# 분석 결과 생성
log_info "Generating analysis report..."
cat > "$OUTPUT_FILE" <<EOF
# SMTP 패킷 분석 보고서
- 분석 시간: $(iso8601_now)
- 공격 ID: $ATTACK_ID
- 분석 파일: $PCAP_FILE
- 파일 크기: $PCAP_SIZE bytes

## 메타데이터 및 통계
- 총 패킷 수: $TOTAL_PACKETS
- SMTP 관련 패킷 수: $SMTP_PACKETS

## SMTP 명령 및 응답 시퀀스
\`\`\`
$(if [ -n "$SMTP_COMMANDS" ] || [ -n "$SMTP_RESPONSES" ]; then
    echo "=== SMTP 명령어 ==="
    echo "$SMTP_COMMANDS"
    echo ""
    echo "=== SMTP 응답 ==="
    echo "$SMTP_RESPONSES"
    echo ""
    echo "=== 응답 코드 통계 ==="
    echo "- 2xx (성공): $RESPONSE_2XX"
    echo "- 4xx (일시적 실패): $RESPONSE_4XX"
    echo "- 5xx (영구적 실패): $RESPONSE_5XX"
    echo "- 릴레이/액세스 거부: $RELAY_DENIALS"
    echo "- 인증 실패: $AUTH_FAILURES"
    echo ""
    echo "=== 전체 SMTP 트래픽 ==="
    echo "$MAIL_CONTENT"
else
    echo "(SMTP 트래픽이 감지되지 않았습니다)"
fi)
\`\`\`

## 메일 내용 (있는 경우)
\`\`\`
$(if [ -s "$TEMP_FILE" ]; then
    echo "패킷 수: $SMTP_PACKETS"
    echo "상세 내용은 tshark 분석 필요"
else
    echo "(캡처된 메일 내용 없음)"
fi)
\`\`\`

## JSON 요약
\`\`\`json
{
    "event_type": "smtp_analysis_complete",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$(iso8601_now)",
    "pcap_file": "$PCAP_FILE",
    "output_file": "$OUTPUT_FILE",
    "statistics": {
        "total_packets": $TOTAL_PACKETS,
        "smtp_packets": $SMTP_PACKETS,
        "file_size_bytes": $PCAP_SIZE,
        "response_codes": {
            "success_2xx": $RESPONSE_2XX,
            "temp_failure_4xx": $RESPONSE_4XX,
            "perm_failure_5xx": $RESPONSE_5XX,
            "relay_denials": $RELAY_DENIALS,
            "auth_failures": $AUTH_FAILURES
        }
    },
    "analysis_status": "success"
}
\`\`\`
EOF

log_info "PCAP analysis completed successfully"
log_info "Results written to: $OUTPUT_FILE"

# 정리
rm -f "$TEMP_FILE"

show_script_completion "analyze_pcap.sh" $SCRIPT_START_TIME
exit 0