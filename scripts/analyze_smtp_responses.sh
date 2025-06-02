#!/bin/bash
# SMTP 응답 코드별 카테고리화 및 분석 스크립트

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${SCRIPT_DIR}/../artifacts"
OUTPUT_FILE="${ARTIFACTS_DIR}/smtp_response_analysis.json"

# SMTP 응답 코드 분류 데이터베이스
declare -A SMTP_CODES=(
    # 2xx - 성공 응답
    ["200"]="success:Nonstandard success response"
    ["211"]="success:System status, or system help reply"
    ["214"]="success:Help message"
    ["220"]="success:Service ready"
    ["221"]="success:Service closing transmission channel"
    ["250"]="success:Requested mail action okay, completed"
    ["251"]="success:User not local; will forward"
    ["252"]="success:Cannot VRFY user, but will accept message"

    # 3xx - 중간 응답 (추가 정보 필요)
    ["334"]="intermediate:Authentication mechanism specific data"
    ["354"]="intermediate:Start mail input; end with <CRLF>.<CRLF>"

    # 4xx - 임시 실패 (재시도 가능)
    ["421"]="temp_failure:Service not available, closing transmission"
    ["450"]="temp_failure:Requested mail action not taken: mailbox unavailable"
    ["451"]="temp_failure:Requested action aborted: local error"
    ["452"]="temp_failure:Requested action not taken: insufficient storage"
    ["454"]="temp_failure:Temporary authentication failure"

    # 5xx - 영구 실패 (재시도 불가)
    ["500"]="perm_failure:Syntax error, command unrecognized"
    ["501"]="perm_failure:Syntax error in parameters or arguments"
    ["502"]="perm_failure:Command not implemented"
    ["503"]="perm_failure:Bad sequence of commands"
    ["504"]="perm_failure:Command parameter not implemented"
    ["521"]="perm_failure:Machine does not accept mail"
    ["530"]="perm_failure:Authentication required"
    ["535"]="perm_failure:Authentication credentials invalid"
    ["550"]="perm_failure:Requested action not taken: mailbox unavailable"
    ["551"]="perm_failure:User not local; please try forwarding"
    ["552"]="perm_failure:Requested mail action aborted: exceeded storage"
    ["553"]="perm_failure:Requested action not taken: mailbox name invalid"
    ["554"]="perm_failure:Transaction failed"

    # 보안 관련 특별 코드
    ["550_relay"]="security:Relay access denied"
    ["550_spam"]="security:Message rejected as spam"
    ["554_policy"]="security:Transaction failed due to policy"
)

# 응답 코드 심각도 레벨
declare -A SEVERITY_LEVELS=(
    ["success"]="info"
    ["intermediate"]="info"
    ["temp_failure"]="warning"
    ["perm_failure"]="error"
    ["security"]="critical"
)

log_json() {
    local level="$1"
    local message="$2"
    local details="${3:-}"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local log_entry=$(jq -n \
        --arg timestamp "$timestamp" \
        --arg level "$level" \
        --arg component "smtp_response_analyzer" \
        --arg message "$message" \
        --arg details "$details" \
        '{
            timestamp: $timestamp,
            level: $level,
            component: $component,
            message: $message,
            details: ($details | if . == "" then null else . end)
        }')
    
    echo "$log_entry" | jq -c .
}

extract_smtp_responses() {
    local pcap_file="$1"
    local temp_file="${ARTIFACTS_DIR}/smtp_responses_raw.txt"
    
    log_json "info" "Extracting SMTP responses from PCAP" "$pcap_file"
    
    # tshark로 SMTP 응답 추출
    tshark -r "$pcap_file" -Y "smtp.response" \
        -T fields -e smtp.response.code -e smtp.response.parameter \
        2>/dev/null | grep -v "^$" > "$temp_file" || true
    
    if [[ ! -s "$temp_file" ]]; then
        log_json "warning" "No SMTP responses found in PCAP file"
        return 1
    fi
    
    echo "$temp_file"
}

analyze_response_codes() {
    local responses_file="$1"
    local analysis_data="[]"
    
    log_json "info" "Analyzing SMTP response codes"
    
    declare -A code_counts
    declare -A category_counts
    declare -A severity_counts
    
    # 응답 코드별 카운트
    while IFS=$'\t' read -r code message; do
        [[ -z "$code" ]] && continue
        
        # 정규화된 코드 (보안 관련 특별 처리)
        normalized_code="$code"
        if [[ "$message" =~ [Rr]elay ]]; then
            normalized_code="${code}_relay"
        elif [[ "$message" =~ [Ss]pam ]]; then
            normalized_code="${code}_spam"
        elif [[ "$message" =~ [Pp]olicy ]]; then
            normalized_code="${code}_policy"
        fi
        
        ((code_counts["$normalized_code"]++)) || code_counts["$normalized_code"]=1
        
        # 카테고리 및 심각도 분류
        if [[ -n "${SMTP_CODES[$normalized_code]:-}" ]]; then
            local category="${SMTP_CODES[$normalized_code]%%:*}"
            local severity="${SEVERITY_LEVELS[$category]:-unknown}"
            
            ((category_counts["$category"]++)) || category_counts["$category"]=1
            ((severity_counts["$severity"]++)) || severity_counts["$severity"]=1
        else
            ((category_counts["unknown"]++)) || category_counts["unknown"]=1
            ((severity_counts["unknown"]++)) || severity_counts["unknown"]=1
        fi
    done < "$responses_file"
    
    # JSON 결과 생성
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # 개별 코드 분석
    local codes_json="[]"
    for code in "${!code_counts[@]}"; do
        local count="${code_counts[$code]}"
        local category="unknown"
        local description="Unknown response code"
        local severity="unknown"
        
        if [[ -n "${SMTP_CODES[$code]:-}" ]]; then
            category="${SMTP_CODES[$code]%%:*}"
            description="${SMTP_CODES[$code]#*:}"
            severity="${SEVERITY_LEVELS[$category]:-unknown}"
        fi
        
        codes_json=$(echo "$codes_json" | jq \
            --arg code "$code" \
            --arg count "$count" \
            --arg category "$category" \
            --arg description "$description" \
            --arg severity "$severity" \
            '. += [{
                code: $code,
                count: ($count | tonumber),
                category: $category,
                description: $description,
                severity: $severity
            }]')
    done
    
    # 카테고리별 통계
    local categories_json="[]"
    for category in "${!category_counts[@]}"; do
        local count="${category_counts[$category]}"
        categories_json=$(echo "$categories_json" | jq \
            --arg category "$category" \
            --arg count "$count" \
            '. += [{
                category: $category,
                count: ($count | tonumber)
            }]')
    done
    
    # 심각도별 통계
    local severities_json="[]"
    for severity in "${!severity_counts[@]}"; do
        local count="${severity_counts[$severity]}"
        severities_json=$(echo "$severities_json" | jq \
            --arg severity "$severity" \
            --arg count "$count" \
            '. += [{
                severity: $severity,
                count: ($count | tonumber)
            }]')
    done
    
    # 최종 결과 조합
    local result=$(jq -n \
        --arg timestamp "$timestamp" \
        --argjson codes "$codes_json" \
        --argjson categories "$categories_json" \
        --argjson severities "$severities_json" \
        '{
            analysis_timestamp: $timestamp,
            smtp_response_analysis: {
                summary: {
                    total_responses: ($codes | map(.count) | add // 0),
                    unique_codes: ($codes | length),
                    categories: ($categories | sort_by(.category)),
                    severities: ($severities | sort_by(.severity))
                },
                detailed_codes: ($codes | sort_by(.code)),
                recommendations: []
            }
        }')
    
    # 권장사항 생성
    if [[ -n "${category_counts[security]:-}" ]]; then
        result=$(echo "$result" | jq '.smtp_response_analysis.recommendations += ["보안 관련 응답 코드가 감지되었습니다. 서버 설정을 검토하세요."]')
    fi
    
    if [[ -n "${code_counts[550_relay]:-}" ]]; then
        result=$(echo "$result" | jq '.smtp_response_analysis.recommendations += ["오픈 릴레이 거부 응답이 감지되었습니다. 보안 설정이 적절히 작동하고 있습니다."]')
    fi
    
    if [[ -n "${category_counts[perm_failure]:-}" && "${category_counts[perm_failure]}" -gt 5 ]]; then
        result=$(echo "$result" | jq '.smtp_response_analysis.recommendations += ["다수의 영구 실패 응답이 감지되었습니다. 클라이언트 설정이나 인증을 확인하세요."]')
    fi
    
    echo "$result"
}

main() {
    local pcap_file="${1:-}"
    
    if [[ -z "$pcap_file" ]]; then
        echo "Usage: $0 <pcap_file>"
        echo "Analyzes SMTP response codes from packet capture file"
        exit 1
    fi
    
    if [[ ! -f "$pcap_file" ]]; then
        log_json "error" "PCAP file not found" "$pcap_file"
        exit 1
    fi
    
    mkdir -p "$ARTIFACTS_DIR"
    
    log_json "info" "Starting SMTP response code analysis" "$pcap_file"
    
    # SMTP 응답 추출
    local responses_file
    if ! responses_file=$(extract_smtp_responses "$pcap_file"); then
        log_json "error" "Failed to extract SMTP responses"
        exit 1
    fi
    
    # 응답 코드 분석
    local analysis_result
    analysis_result=$(analyze_response_codes "$responses_file")
    
    # 결과 저장
    echo "$analysis_result" > "$OUTPUT_FILE"
    log_json "info" "Analysis completed" "$OUTPUT_FILE"
    
    # 간단한 요약 출력
    echo "$analysis_result" | jq -r '
        .smtp_response_analysis.summary | 
        "Total responses: \(.total_responses)\nUnique codes: \(.unique_codes)\nCategories: \(.categories | map("\(.category): \(.count)") | join(", "))"'
    
    # 정리
    rm -f "$responses_file"
}

main "$@"
