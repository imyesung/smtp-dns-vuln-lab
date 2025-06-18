#!/bin/bash
# scripts/gen_report_html.sh

# 사용법 검사
if [ "$#" -ne 4 ]; then
    echo "사용법: $0 <실행_ID> <강화_전_분석_파일> <강화_후_분석_파일> <아티팩트_디렉토리>"
    echo "예: $0 EXP_20230101_120000 ./artifacts/analysis_EXP_20230101_120000_BEFORE.txt ./artifacts/analysis_EXP_20230101_120000_AFTER.txt ./artifacts"
    exit 1
fi

RUN_ID="$1"
BEFORE_ANALYSIS_FILE="$2"
AFTER_ANALYSIS_FILE="$3"
ARTIFACTS_DIR="$4"

REPORT_FILE="${ARTIFACTS_DIR}/security_assessment_${RUN_ID}.html"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# HTML 이스케이프 함수
escape_html() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'\''/\&#39;/g'
}

# 분석 파일 내용 포맷팅
format_analysis_content() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "<p class='error'>파일을 찾을 수 없음: $file</p>"
        return
    fi
    
    local content=$(cat "$file" | escape_html)
    echo "$content" | sed 's/^/<p>/' | sed 's/$/<\/p>/' | \
    sed 's/=== \([^=]*\) ===/<h4>\1<\/h4>/g' | \
    sed 's/--- \([^-]*\) ---/<h5>\1<\/h5>/g' | \
    sed 's/^\s*$/<hr\/>/g'
}

# 환경 정보 수집
collect_environment_info() {
    echo "<div class='env-info'>"
    echo "<strong>실행 환경:</strong><br>"
    echo "Host: $(hostname)<br>"
    echo "Date: $(date)<br>"
    echo "Docker: $(docker --version 2>/dev/null || echo 'Not available')<br>"
    echo "</div>"
}

# 실험 아티팩트 스캔
scan_experiment_artifacts() {
    local artifacts=""
    artifacts+="<div class='artifacts-list'>"
    artifacts+="<strong>생성된 파일:</strong><ul>"
    
    for file in $(find "$ARTIFACTS_DIR" -name "*${RUN_ID}*" -type f 2>/dev/null | sort); do
        local filename=$(basename "$file")
        local filesize=$(ls -lh "$file" | awk '{print $5}')
        artifacts+="<li>$filename ($filesize)</li>"
    done
    
    artifacts+="</ul></div>"
    echo "$artifacts"
}

# 공격 결과 분석 (포멀한 버전)
collect_attack_results() {
    local results=""
    
    results+="<h3>Attack Vector Analysis</h3>"
    results+="<div class='attack-analysis'>"
    
    # Open Relay 분석
    local relay_before=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    local relay_after=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    results+="<div class='attack-vector'>"
    results+="<h4>Open Relay Vulnerability</h4>"
    
    if [ -f "$relay_before" ] || [ -f "$relay_after" ]; then
        local before_status="UNTESTED"
        local after_status="UNTESTED"
        local before_success=0
        local after_success=0
        local before_blocked=0
        local after_blocked=0
        
        if [ -f "$relay_before" ]; then
            before_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_before" 2>/dev/null || echo "0")
            before_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_before" 2>/dev/null || echo "0")
            
            if [ "$before_success" -gt 0 ]; then
                before_status="VULNERABLE"
            elif [ "$before_blocked" -gt 0 ]; then
                before_status="SECURE"
            fi
        fi
        
        if [ -f "$relay_after" ]; then
            after_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_after" 2>/dev/null || echo "0")
            after_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_after" 2>/dev/null || echo "0")
            
            if [ "$after_success" -gt 0 ]; then
                after_status="VULNERABLE"
            elif [ "$after_blocked" -gt 0 ]; then
                after_status="SECURE"
            fi
        fi
        
        results+="<div class='status-comparison'>"
        results+="<div class='status-before status-$before_status'>Before: $before_status</div>"
        results+="<div class='status-arrow'>→</div>"
        results+="<div class='status-after status-$after_status'>After: $after_status</div>"
        results+="</div>"
        
        # 개선 상태 판정
        if [ "$before_status" = "VULNERABLE" ] && [ "$after_status" = "SECURE" ]; then
            results+="<div class='improvement-status improved'>VULNERABILITY REMEDIATED</div>"
        elif [ "$before_status" = "SECURE" ] && [ "$after_status" = "SECURE" ]; then
            results+="<div class='improvement-status maintained'>SECURITY MAINTAINED</div>"
        elif [ "$before_status" = "VULNERABLE" ] && [ "$after_status" = "VULNERABLE" ]; then
            results+="<div class='improvement-status failed'>VULNERABILITY PERSISTS</div>"
        else
            results+="<div class='improvement-status unknown'>INCONCLUSIVE</div>"
        fi
        
        results+="<div class='technical-details'>"
        results+="Success Count: $before_success → $after_success<br>"
        results+="Block Count: $before_blocked → $after_blocked"
        results+="</div>"
        
    else
        results+="<div class='status-comparison'>"
        results+="<div class='status-unavailable'>TEST DATA UNAVAILABLE</div>"
        results+="</div>"
    fi
    results+="</div>"
    
    # STARTTLS 분석
    local starttls_before="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_BEFORE.txt"
    local starttls_after="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_AFTER.txt"
    
    if [ ! -f "$starttls_before" ]; then
        starttls_before=$(ls "${ARTIFACTS_DIR}"/*starttls*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    fi
    if [ ! -f "$starttls_after" ]; then
        starttls_after=$(ls "${ARTIFACTS_DIR}"/*starttls*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    fi
    
    results+="<div class='attack-vector'>"
    results+="<h4>STARTTLS Downgrade Attack</h4>"
    
    if [ -f "$starttls_before" ] || [ -f "$starttls_after" ]; then
        local before_vuln="UNTESTED"
        local after_vuln="UNTESTED"
        
        if [ -f "$starttls_before" ]; then
            if grep -q "VULNERABLE\|HIGHLY VULNERABLE" "$starttls_before" 2>/dev/null; then
                before_vuln="VULNERABLE"
            elif grep -q "SECURE" "$starttls_before" 2>/dev/null; then
                before_vuln="SECURE"
            fi
        fi
        
        if [ -f "$starttls_after" ]; then
            if grep -q "VULNERABLE\|HIGHLY VULNERABLE" "$starttls_after" 2>/dev/null; then
                after_vuln="VULNERABLE"
            elif grep -q "SECURE" "$starttls_after" 2>/dev/null; then
                after_vuln="SECURE"
            fi
        fi
        
        results+="<div class='status-comparison'>"
        results+="<div class='status-before status-$before_vuln'>Before: $before_vuln</div>"
        results+="<div class='status-arrow'>→</div>"
        results+="<div class='status-after status-$after_vuln'>After: $after_vuln</div>"
        results+="</div>"
        
        if [ "$before_vuln" = "VULNERABLE" ] && [ "$after_vuln" = "SECURE" ]; then
            results+="<div class='improvement-status improved'>TLS SECURITY ENHANCED</div>"
        elif [ "$before_vuln" = "SECURE" ] && [ "$after_vuln" = "SECURE" ]; then
            results+="<div class='improvement-status maintained'>TLS SECURITY MAINTAINED</div>"
        elif [ "$before_vuln" = "VULNERABLE" ] && [ "$after_vuln" = "VULNERABLE" ]; then
            results+="<div class='improvement-status failed'>TLS VULNERABILITY PERSISTS</div>"
        fi
    else
        results+="<div class='status-comparison'>"
        results+="<div class='status-unavailable'>TEST DATA UNAVAILABLE</div>"
        results+="</div>"
    fi
    results+="</div>"
    
    # 평문 인증 분석
    local auth_patterns=(
        "${ARTIFACTS_DIR}/auth_plain_summary_${RUN_ID}_BEFORE.txt"
        "${ARTIFACTS_DIR}/*auth*${RUN_ID}*BEFORE*.txt"
        "${ARTIFACTS_DIR}/*plaintext*${RUN_ID}*BEFORE*.txt"
    )
    
    local auth_before=""
    local auth_after=""
    
    for pattern in "${auth_patterns[@]}"; do
        local found_file=$(ls $pattern 2>/dev/null | head -1)
        if [ -f "$found_file" ]; then
            auth_before="$found_file"
            auth_after="${found_file/BEFORE/AFTER}"
            break
        fi
    done
    
    results+="<div class='attack-vector'>"
    results+="<h4>Plaintext Authentication</h4>"
    
    if [ -f "$auth_before" ] || [ -f "$auth_after" ]; then
        local before_auth="UNTESTED"
        local after_auth="UNTESTED"
        
        if [ -f "$auth_before" ]; then
            if grep -q "HIGHLY VULNERABLE\|VULNERABLE\|235.*Authentication successful\|평문.*허용" "$auth_before" 2>/dev/null; then
                before_auth="VULNERABLE"
            elif grep -q "SECURE\|530.*TLS.*required\|TLS.*필수" "$auth_before" 2>/dev/null; then
                before_auth="SECURE"
            fi
        fi
        
        if [ -f "$auth_after" ]; then
            if grep -q "HIGHLY VULNERABLE\|VULNERABLE\|235.*Authentication successful\|평문.*허용" "$auth_after" 2>/dev/null; then
                after_auth="VULNERABLE"
            elif grep -q "SECURE\|530.*TLS.*required\|TLS.*필수" "$auth_after" 2>/dev/null; then
                after_auth="SECURE"
            fi
        fi
        
        results+="<div class='status-comparison'>"
        results+="<div class='status-before status-$before_auth'>Before: $before_auth</div>"
        results+="<div class='status-arrow'>→</div>"
        results+="<div class='status-after status-$after_auth'>After: $after_auth</div>"
        results+="</div>"
        
        if [ "$before_auth" = "VULNERABLE" ] && [ "$after_auth" = "SECURE" ]; then
            results+="<div class='improvement-status improved'>TLS AUTHENTICATION ENFORCED</div>"
        elif [ "$before_auth" = "SECURE" ] && [ "$after_auth" = "SECURE" ]; then
            results+="<div class='improvement-status maintained'>TLS AUTHENTICATION MAINTAINED</div>"
        fi
    else
        results+="<div class='status-comparison'>"
        results+="<div class='status-unavailable'>TEST DATA UNAVAILABLE</div>"
        results+="</div>"
    fi
    results+="</div>"
    
    results+="</div>"
    echo "$results"
}

# CVSS 점수 분석 (포멀한 버전)
collect_cvss_scores() {
    local cvss_results=""
    
    cvss_results+="<h3>Risk Assessment (CVSS 3.1)</h3>"
    cvss_results+="<div class='cvss-analysis'>"
    
    local vulnerabilities_found=()
    local total_cvss_score=0.0
    local max_severity="None"
    
    # Open Relay 취약점 확인
    local relay_vuln_found=false
    local relay_after_file=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    if [ -f "$relay_after_file" ]; then
        local after_success_count=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|250.*Message.*accepted' "$relay_after_file" 2>/dev/null || echo "0")
        if [ "$after_success_count" -gt 0 ]; then
            relay_vuln_found=true
        fi
    else
        for relay_file in $(find "$ARTIFACTS_DIR" -name "*relay*${RUN_ID}*" -type f 2>/dev/null); do
            local success_count=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|250.*Message.*accepted' "$relay_file" 2>/dev/null || echo "0")
            if [ "$success_count" -gt 0 ]; then
                relay_vuln_found=true
                break
            fi
        done
    fi
    
    if [ "$relay_vuln_found" = true ]; then
        vulnerabilities_found+=("Open Relay")
        total_cvss_score=$(echo "$total_cvss_score + 7.5" | bc -l 2>/dev/null || echo "7.5")
        max_severity="High"
    fi
    
    # STARTTLS 다운그레이드 취약점
    if find "$ARTIFACTS_DIR" -name "*starttls*${RUN_ID}*" -type f -exec grep -l "VULNERABLE\|HIGHLY VULNERABLE" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("STARTTLS Downgrade")
        total_cvss_score=$(echo "$total_cvss_score + 8.1" | bc -l 2>/dev/null || echo "$total_cvss_score")
        max_severity="High"
    fi
    
    # 평문 인증 취약점
    if find "$ARTIFACTS_DIR" -name "*auth*${RUN_ID}*" -o -name "*plaintext*${RUN_ID}*" -type f -exec grep -l "HIGHLY VULNERABLE\|235.*successful" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("Plaintext Authentication")
        total_cvss_score=$(echo "$total_cvss_score + 7.8" | bc -l 2>/dev/null || echo "$total_cvss_score")
        max_severity="High"
    fi
    
    # DNS 재귀 취약점
    if find "$ARTIFACTS_DIR" -name "*dns*${RUN_ID}*" -type f -exec grep -l "VULNERABLE.*recursion\|재귀.*허용" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("DNS Recursion")
        total_cvss_score=$(echo "$total_cvss_score + 5.3" | bc -l 2>/dev/null || echo "$total_cvss_score")
        if [ "$max_severity" = "None" ]; then max_severity="Medium"; fi
    fi
    
    # 평균 CVSS 점수 계산
    local avg_cvss_score=0.0
    if [ ${#vulnerabilities_found[@]} -gt 0 ]; then
        avg_cvss_score=$(echo "scale=1; $total_cvss_score / ${#vulnerabilities_found[@]}" | bc -l 2>/dev/null || echo "0.0")
    fi
    
    cvss_results+="<div class='cvss-summary'>"
    cvss_results+="<div class='cvss-metric'>"
    cvss_results+="<div class='metric-label'>Vulnerabilities Identified</div>"
    cvss_results+="<div class='metric-value'>${#vulnerabilities_found[@]}</div>"
    cvss_results+="</div>"
    
    cvss_results+="<div class='cvss-metric'>"
    cvss_results+="<div class='metric-label'>Average CVSS Score</div>"
    cvss_results+="<div class='metric-value'>$avg_cvss_score</div>"
    cvss_results+="</div>"
    
    cvss_results+="<div class='cvss-metric'>"
    cvss_results+="<div class='metric-label'>Maximum Severity</div>"
    cvss_results+="<div class='metric-value severity-$max_severity'>$max_severity</div>"
    cvss_results+="</div>"
    cvss_results+="</div>"
    
    if [ ${#vulnerabilities_found[@]} -gt 0 ]; then
        cvss_results+="<div class='vulnerability-list'>"
        cvss_results+="<h4>Identified Vulnerabilities:</h4><ul>"
        for vuln in "${vulnerabilities_found[@]}"; do
            cvss_results+="<li>$vuln</li>"
        done
        cvss_results+="</ul></div>"
    fi
    
    cvss_results+="</div>"
    echo "$cvss_results"
}

# 하드닝 효과 분석
collect_hardening_effectiveness() {
    local hardening_results=""
    
    hardening_results+="<h3>Security Hardening Assessment</h3>"
    hardening_results+="<div class='hardening-analysis'>"
    
    local improvements=0
    local already_secure=0
    local total_tests=0
    local detailed_analysis=""
    
    # Open Relay 개선 확인
    local relay_before=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    local relay_after=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    if [ -f "$relay_before" ] && [ -f "$relay_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='hardening-measure'>"
        detailed_analysis+="<div class='measure-name'>Open Relay Protection</div>"
        
        local before_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_before" 2>/dev/null || echo "0")
        local after_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_after" 2>/dev/null || echo "0")
        local before_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_before" 2>/dev/null || echo "0")
        local after_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_after" 2>/dev/null || echo "0")
        
        if [ "$before_success" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status improved'>IMPLEMENTED</div>"
            improvements=$((improvements + 1))
        elif [ "$before_blocked" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status maintained'>MAINTAINED</div>"
            already_secure=$((already_secure + 1))
        elif [ "$before_success" -gt 0 ] && [ "$after_success" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status failed'>INEFFECTIVE</div>"
        else
            detailed_analysis+="<div class='measure-status unknown'>INCONCLUSIVE</div>"
        fi
        detailed_analysis+="</div>"
    fi
    
    # STARTTLS 개선 확인
    local starttls_before="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_BEFORE.txt"
    local starttls_after="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_AFTER.txt"
    
    if [ -f "$starttls_before" ] && [ -f "$starttls_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='hardening-measure'>"
        detailed_analysis+="<div class='measure-name'>TLS Enforcement</div>"
        
        local before_vuln=$(grep -c "VULNERABLE" "$starttls_before" 2>/dev/null || echo "0")
        local after_secure=$(grep -c "SECURE" "$starttls_after" 2>/dev/null || echo "0")
        
        if [ "$before_vuln" -gt 0 ] && [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status improved'>IMPLEMENTED</div>"
            improvements=$((improvements + 1))
        elif [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status maintained'>MAINTAINED</div>"
            already_secure=$((already_secure + 1))
        else
            detailed_analysis+="<div class='measure-status failed'>INEFFECTIVE</div>"
        fi
        detailed_analysis+="</div>"
    fi
    
    # 인증 보안 개선 확인
    local auth_before="${ARTIFACTS_DIR}/auth_plain_summary_${RUN_ID}_BEFORE.txt"
    local auth_after="${ARTIFACTS_DIR}/auth_plain_summary_${RUN_ID}_AFTER.txt"
    
    if [ -f "$auth_before" ] && [ -f "$auth_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='hardening-measure'>"
        detailed_analysis+="<div class='measure-name'>Authentication Security</div>"
        
        local before_vuln=$(grep -c "VULNERABLE" "$auth_before" 2>/dev/null || echo "0")
        local after_secure=$(grep -c "SECURE" "$auth_after" 2>/dev/null || echo "0")
        
        if [ "$before_vuln" -gt 0 ] && [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status improved'>IMPLEMENTED</div>"
            improvements=$((improvements + 1))
        elif [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="<div class='measure-status maintained'>MAINTAINED</div>"
            already_secure=$((already_secure + 1))
        else
            detailed_analysis+="<div class='measure-status failed'>INEFFECTIVE</div>"
        fi
        detailed_analysis+="</div>"
    fi
    
    hardening_results+="$detailed_analysis"
    
    # 종합 효과성 평가
    local effectiveness_percentage=0
    local total_security_actions=$((improvements + already_secure))
    
    if [ "$total_tests" -gt 0 ]; then
        effectiveness_percentage=$(( (total_security_actions * 100) / total_tests ))
    fi
    
    hardening_results+="<div class='effectiveness-summary'>"
    hardening_results+="<div class='effectiveness-metric'>"
    hardening_results+="<div class='metric-label'>Security Measures Tested</div>"
    hardening_results+="<div class='metric-value'>$total_tests</div>"
    hardening_results+="</div>"
    
    hardening_results+="<div class='effectiveness-metric'>"
    hardening_results+="<div class='metric-label'>New Implementations</div>"
    hardening_results+="<div class='metric-value'>$improvements</div>"
    hardening_results+="</div>"
    
    hardening_results+="<div class='effectiveness-metric'>"
    hardening_results+="<div class='metric-label'>Security Maintained</div>"
    hardening_results+="<div class='metric-value'>$already_secure</div>"
    hardening_results+="</div>"
    
    hardening_results+="<div class='effectiveness-metric'>"
    hardening_results+="<div class='metric-label'>Overall Effectiveness</div>"
    hardening_results+="<div class='metric-value'>$effectiveness_percentage%</div>"
    hardening_results+="</div>"
    hardening_results+="</div>"
    
    # 전반적 평가
    hardening_results+="<div class='overall-assessment "
    if [ "$effectiveness_percentage" -ge 75 ]; then
        if [ "$improvements" -gt "$already_secure" ]; then
            hardening_results+="excellent'>EXCELLENT - Significant security improvements implemented</div>"
        else
            hardening_results+="good'>GOOD - Strong security posture maintained</div>"
        fi
    elif [ "$effectiveness_percentage" -ge 50 ]; then
        hardening_results+="satisfactory'>SATISFACTORY - Partial security enhancements</div>"
    elif [ "$already_secure" -gt 0 ]; then
        hardening_results+="baseline'>BASELINE - Existing security measures maintained</div>"
    else
        hardening_results+="insufficient'>INSUFFICIENT - Limited security improvement</div>"
    fi
    
    hardening_results+="</div>"
    echo "$hardening_results"
}

BEFORE_CONTENT_HTML=$(format_analysis_content "$BEFORE_ANALYSIS_FILE")
AFTER_CONTENT_HTML=$(format_analysis_content "$AFTER_ANALYSIS_FILE")

ATTACK_RESULTS_HTML=$(collect_attack_results)
CVSS_SCORES_HTML=$(collect_cvss_scores)
HARDENING_EFFECTIVENESS_HTML=$(collect_hardening_effectiveness)
EXPERIMENT_ARTIFACTS_HTML=$(scan_experiment_artifacts)
ENVIRONMENT_INFO_HTML=$(collect_environment_info)

DIFF_CONTENT_HTML="<p>비교할 분석 파일 중 하나 또는 둘 다를 찾을 수 없습니다.</p>"
if [ -f "$BEFORE_ANALYSIS_FILE" ] && [ -f "$AFTER_ANALYSIS_FILE" ]; then
    DIFF_OUTPUT=$(diff -u "$BEFORE_ANALYSIS_FILE" "$AFTER_ANALYSIS_FILE" || true) # diff가 차이점을 발견하면 0이 아닌 값을 반환할 수 있으므로 || true
    if [ -z "$DIFF_OUTPUT" ]; then
        DIFF_CONTENT_HTML="<p>강화 전후 분석 파일 간에 차이점이 없습니다.</p>"
    else
        DIFF_CONTENT_HTML="<pre>$(echo "$DIFF_OUTPUT" | escape_html)</pre>"
    fi
fi

# Docker ps 결과
DOCKER_PS_OUTPUT=$(docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | escape_html)
if [ -z "$DOCKER_PS_OUTPUT" ]; then
    DOCKER_PS_OUTPUT="Docker 컨테이너 정보를 가져올 수 없습니다. Docker가 실행 중인지, 현재 디렉토리에 docker-compose.yml 파일이 있는지 확인하세요."
fi

# 강화 전/후 판단 로직 개선 (SMTP 세션 단계별 분석)
BEFORE_SMTP_CMDS_COUNT=0
AFTER_SMTP_CMDS_COUNT=0
BEFORE_HAS_PACKETS=false
AFTER_HAS_PACKETS=false
BEFORE_REJECT_COUNT=0
AFTER_REJECT_COUNT=0
BEFORE_DATA_ATTEMPTS=0
AFTER_DATA_ATTEMPTS=0
BEFORE_AUTH_FAILURES=0
AFTER_AUTH_FAILURES=0

if [ -f "$BEFORE_ANALYSIS_FILE" ]; then
    BEFORE_SMTP_CMDS_COUNT=$(grep -c "MAIL FROM\|RCPT TO\|DATA" "$BEFORE_ANALYSIS_FILE" 2>/dev/null || echo "0")
    BEFORE_DATA_ATTEMPTS=$(grep -c "DATA" "$BEFORE_ANALYSIS_FILE" 2>/dev/null || echo "0")
    # 5xx 오류 응답 (거부) 카운트 - 공백 제거
    BEFORE_REJECT_COUNT=$(grep -o "5[0-9][0-9]" "$BEFORE_ANALYSIS_FILE" 2>/dev/null | wc -l | tr -d ' \t' || echo "0")
    # 인증 관련 오류 카운트 - 공백 제거
    BEFORE_AUTH_FAILURES=$(grep -ci "authentication\|access denied" "$BEFORE_ANALYSIS_FILE" 2>/dev/null | tr -d ' \t' || echo "0")
    # 패킷이 있는지 확인
    before_total_packets=$(grep "총 패킷 수:" "$BEFORE_ANALYSIS_FILE" | grep -o '[0-9]\+' | head -1 || echo "0")
    [ "$before_total_packets" -gt 0 ] && BEFORE_HAS_PACKETS=true
fi

if [ -f "$AFTER_ANALYSIS_FILE" ]; then
    AFTER_SMTP_CMDS_COUNT=$(grep -c "MAIL FROM\|RCPT TO\|DATA" "$AFTER_ANALYSIS_FILE" 2>/dev/null || echo "0")
    AFTER_DATA_ATTEMPTS=$(grep -c "DATA" "$AFTER_ANALYSIS_FILE" 2>/dev/null || echo "0")
    # 5xx 오류 응답 (거부) 카운트 - 공백 제거
    AFTER_REJECT_COUNT=$(grep -o "5[0-9][0-9]" "$AFTER_ANALYSIS_FILE" 2>/dev/null | wc -l | tr -d ' \t' || echo "0")
    # 인증 관련 오류 카운트 - 공백 제거
    AFTER_AUTH_FAILURES=$(grep -ci "authentication\|access denied" "$AFTER_ANALYSIS_FILE" 2>/dev/null | tr -d ' \t' || echo "0")
    # 패킷이 있는지 확인
    after_total_packets=$(grep "총 패킷 수:" "$AFTER_ANALYSIS_FILE" | grep -o '[0-9]\+' | head -1 || echo "0")
    [ "$after_total_packets" -gt 0 ] && AFTER_HAS_PACKETS=true
fi

# 보안 강화 효과 분석 (상세)
reject_increase=$((AFTER_REJECT_COUNT - BEFORE_REJECT_COUNT))
cmd_decrease=$((BEFORE_SMTP_CMDS_COUNT - AFTER_SMTP_CMDS_COUNT))
data_cmd_decrease=$((BEFORE_DATA_ATTEMPTS - AFTER_DATA_ATTEMPTS))
auth_failure_increase=$((AFTER_AUTH_FAILURES - BEFORE_AUTH_FAILURES))

# 종합적 보안 점수 계산 (0-100)
security_score=0
if [ "$reject_increase" -gt 0 ]; then
    security_score=$((security_score + 40))  # 거부 응답 증가는 강력한 보안 지표
fi
if [ "$data_cmd_decrease" -gt 0 ]; then
    security_score=$((security_score + 30))  # DATA 명령 차단은 중요한 지표
fi
if [ "$auth_failure_increase" -gt 0 ]; then
    security_score=$((security_score + 20))  # 인증 실패 증가도 보안 강화 지표
fi
if [ "$cmd_decrease" -gt 0 ]; then
    security_score=$((security_score + 10))  # 전반적인 명령 감소
fi

# 개선된 판단 로직 (종합적 분석)
if [ "$BEFORE_HAS_PACKETS" = false ] && [ "$AFTER_HAS_PACKETS" = false ]; then
    VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 실험 데이터 부족</b> 강화 전후 모두 패킷이 캡처되지 않아 보안 강화 효과를 판단할 수 없습니다.</p>"
elif [ "$BEFORE_HAS_PACKETS" = false ]; then
    VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 강화 전 데이터 없음</b> 강화 전 테스트에서 패킷이 캡처되지 않았습니다.</p>"
elif [ "$AFTER_HAS_PACKETS" = false ]; then
    VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 보안 강화 성공 (추정)</b> 강화 후 패킷이 캡처되지 않아 공격이 완전히 차단된 것으로 보입니다.</p>"
elif [ "$security_score" -ge 70 ]; then
    VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 강력한 보안 강화 달성!</b> 보안 점수: $security_score/100 - 다층적 보안 개선 확인</p>"
elif [ "$security_score" -ge 40 ]; then
    VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 보안 강화 성공!</b> 보안 점수: $security_score/100 - 5xx 거부 응답 증가 또는 DATA 명령 차단 확인</p>"
elif [ "$security_score" -ge 20 ]; then
    VERDICT="<p class='partial-success' style='color:#ff8c00; font-weight:bold;'><b>🔶 부분적 보안 개선</b> 보안 점수: $security_score/100 - 일부 차단되나 추가 보안 조치 권장</p>"
elif [ "$BEFORE_SMTP_CMDS_COUNT" -gt 0 ] && [ "$AFTER_SMTP_CMDS_COUNT" -eq 0 ]; then
    VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 보안 강화 성공!</b> 강화 전에는 취약했으나 강화 후 완전히 보호됨</p>"
else
    VERDICT="<p class='failure' style='color:red; font-weight:bold;'><b>❌ 보안 강화 실패</b> 보안 점수: $security_score/100 - 강화 후에도 메일 명령이 실행 가능하며 거부 응답 증가 없음</p>"
fi

# 패킷 수 비교를 위한 변수 설정 개선
before_packets="0"
after_packets="0"

# 총 패킷 수 추출 (메타데이터에서)
if [ -f "$BEFORE_ANALYSIS_FILE" ]; then
    before_packets=$(grep "총 패킷 수:" "$BEFORE_ANALYSIS_FILE" | grep -o '[0-9]\+' | head -1 || echo "0")
fi

if [ -f "$AFTER_ANALYSIS_FILE" ]; then
    after_packets=$(grep "총 패킷 수:" "$AFTER_ANALYSIS_FILE" | grep -o '[0-9]\+' | head -1 || echo "0")
fi

# 공백 제거 및 기본값 설정 (향상된 버전)
before_packets=${before_packets:-0}
after_packets=${after_packets:-0}

# 숫자가 아닌 값들을 0으로 초기화
[[ "$before_packets" =~ ^[0-9]+$ ]] || before_packets=0
[[ "$after_packets" =~ ^[0-9]+$ ]] || after_packets=0
[[ "$BEFORE_SMTP_CMDS_COUNT" =~ ^[0-9]+$ ]] || BEFORE_SMTP_CMDS_COUNT=0
[[ "$AFTER_SMTP_CMDS_COUNT" =~ ^[0-9]+$ ]] || AFTER_SMTP_CMDS_COUNT=0
[[ "$BEFORE_REJECT_COUNT" =~ ^[0-9]+$ ]] || BEFORE_REJECT_COUNT=0
[[ "$AFTER_REJECT_COUNT" =~ ^[0-9]+$ ]] || AFTER_REJECT_COUNT=0
[[ "$BEFORE_DATA_ATTEMPTS" =~ ^[0-9]+$ ]] || BEFORE_DATA_ATTEMPTS=0
[[ "$AFTER_DATA_ATTEMPTS" =~ ^[0-9]+$ ]] || AFTER_DATA_ATTEMPTS=0
[[ "$BEFORE_AUTH_FAILURES" =~ ^[0-9]+$ ]] || BEFORE_AUTH_FAILURES=0
[[ "$AFTER_AUTH_FAILURES" =~ ^[0-9]+$ ]] || AFTER_AUTH_FAILURES=0

# 디버그 출력 (필요시)
# echo "DEBUG: before_packets='$before_packets', after_packets='$after_packets'" >&2

# 숫자 비교 및 판단 로직 (수정된 버전 - 패킷 수 계산 오류 수정)
if [[ "$before_packets" =~ ^[0-9]+$ ]] && [[ "$after_packets" =~ ^[0-9]+$ ]]; then
    # 패킷 수 차이 계산 (before - after로 계산하여 양수면 감소, 음수면 증가)
    packet_diff=$((before_packets - after_packets))
    
    # 동적 임계값 설정 (패킷 수에 따라 조정)
    if [ "$before_packets" -lt 50 ]; then
        min_meaningful_diff=5
        min_percent_change=15
    elif [ "$before_packets" -lt 200 ]; then
        min_meaningful_diff=8
        min_percent_change=10
    else
        min_meaningful_diff=15
        min_percent_change=8
    fi
    
    if [ "$before_packets" -gt 0 ]; then
        # 절대값을 사용하여 퍼센트 계산
        abs_packet_diff=${packet_diff#-}  # 음수 부호 제거
        percent_change=$(( (abs_packet_diff * 100) / before_packets ))
    else
        percent_change=0
    fi
    
    # 보안 강화 효과성 평가 (수정된 로직)
    if [ "$packet_diff" -gt 0 ] && [ "$packet_diff" -ge "$min_meaningful_diff" ] && [ "$percent_change" -ge "$min_percent_change" ]; then
        PACKET_VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 유의미한 트래픽 감소!</b> 패킷 수 $percent_change% 감소 ($before_packets → $after_packets, -$packet_diff 패킷)</p>"
    elif [ "$packet_diff" -gt 0 ] && [ "$packet_diff" -ge 3 ] && [ "$percent_change" -ge 2 ]; then
        # 소폭 감소도 긍정적으로 평가 (SMTP 세션 특성상)
        PACKET_VERDICT="<p class='partial-success' style='color:#ff8c00; font-weight:bold;'><b>🔶 경미한 트래픽 감소</b> 패킷 수 $percent_change% 감소 ($before_packets → $after_packets, -$packet_diff 패킷) - SMTP 세션 최적화 효과</p>"
    elif [ "$packet_diff" -gt 0 ] && [ "$packet_diff" -lt 3 ]; then
        PACKET_VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 미미한 트래픽 변화</b> 패킷 수 소폭 감소 ($before_packets → $after_packets, -$packet_diff 패킷) - TCP 핸드셰이크 차이 수준</p>"
    elif [ "$packet_diff" -eq 0 ]; then
        PACKET_VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 트래픽 변화 없음</b> 강화 전후 패킷 수 동일 ($before_packets) - 응답 코드 분석 필요</p>"
    else
        # packet_diff가 음수인 경우 (트래픽 증가)
        traffic_increase=$((-packet_diff))  # 음수를 양수로 변환
        PACKET_VERDICT="<p class='failure' style='color:red; font-weight:bold;'><b>❌ 트래픽 증가</b> 패킷 수 증가 ($before_packets → $after_packets, +$traffic_increase 패킷) - 예상치 못한 결과</p>"
    fi
else
    PACKET_VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 패킷 수 판단 오류</b> 패킷 수 정보가 유효하지 않음 (before: '$before_packets', after: '$after_packets')</p>"
fi

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Security Assessment Report - $RUN_ID</title>
    <style>
        :root {
            --primary-navy: #1a365d;
            --primary-blue: #2b77ad;
            --accent-teal: #0f4c75;
            --background-gray: #f8fafc;
            --border-light: #e2e8f0;
            --text-dark: #2d3748;
            --text-light: #718096;
            --success-green: #22543d;
            --warning-orange: #c05621;
            --error-red: #742a2a;
            --secure-bg: #f0fff4;
            --vulnerable-bg: #fff5f5;
            --neutral-bg: #f7fafc;
        }
        
        * { box-sizing: border-box; }
        
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0; 
            padding: 20px; 
            background: var(--background-gray);
            color: var(--text-dark); 
            line-height: 1.6; 
        }
        
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            border-radius: 8px;
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-navy) 0%, var(--primary-blue) 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 { 
            margin: 0 0 10px 0; 
            font-size: 2.5rem; 
            font-weight: 300;
            letter-spacing: -0.02em;
        }
        
        .header .subtitle {
            font-size: 1.1rem;
            opacity: 0.9;
            font-weight: 400;
        }
        
        .content-section {
            padding: 30px 40px;
            border-bottom: 1px solid var(--border-light);
        }
        
        .content-section:last-child {
            border-bottom: none;
        }
        
        .section-title {
            font-size: 1.8rem;
            font-weight: 600;
            color: var(--primary-navy);
            margin: 0 0 25px 0;
            padding-bottom: 10px;
            border-bottom: 2px solid var(--primary-blue);
        }
        
        /* Before/After Comparison Chart */
        .comparison-chart {
            display: grid;
            grid-template-columns: 1fr auto 1fr;
            gap: 20px;
            margin: 20px 0;
            align-items: center;
        }
        
        .comparison-side {
            background: var(--neutral-bg);
            padding: 20px;
            border-radius: 8px;
            border: 2px solid var(--border-light);
        }
        
        .comparison-side.before {
            border-left: 4px solid var(--error-red);
        }
        
        .comparison-side.after {
            border-left: 4px solid var(--success-green);
        }
        
        .comparison-arrow {
            font-size: 2rem;
            color: var(--primary-blue);
            font-weight: bold;
        }
        
        .side-title {
            font-weight: 600;
            font-size: 1.1rem;
            margin-bottom: 15px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .side-title.before { color: var(--error-red); }
        .side-title.after { color: var(--success-green); }
        
        /* Attack Analysis */
        .attack-analysis {
            display: grid;
            gap: 20px;
        }
        
        .attack-vector {
            background: white;
            border: 1px solid var(--border-light);
            border-radius: 8px;
            padding: 20px;
        }
        
        .attack-vector h4 {
            margin: 0 0 15px 0;
            color: var(--primary-navy);
            font-size: 1.2rem;
        }
        
        .status-comparison {
            display: flex;
            align-items: center;
            gap: 15px;
            margin: 15px 0;
        }
        
        .status-before, .status-after {
            padding: 8px 16px;
            border-radius: 4px;
            font-weight: 600;
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .status-VULNERABLE { 
            background: var(--vulnerable-bg); 
            color: var(--error-red);
            border: 1px solid #fed7d7;
        }
        
        .status-SECURE { 
            background: var(--secure-bg); 
            color: var(--success-green);
            border: 1px solid #c6f6d5;
        }
        
        .status-UNTESTED { 
            background: var(--neutral-bg); 
            color: var(--text-light);
            border: 1px solid var(--border-light);
        }
        
        .status-unavailable {
            background: #fef5e7;
            color: var(--warning-orange);
            padding: 8px 16px;
            border-radius: 4px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .status-arrow {
            font-size: 1.5rem;
            color: var(--primary-blue);
            font-weight: bold;
        }
        
        .improvement-status {
            margin-top: 10px;
            padding: 8px 12px;
            border-radius: 4px;
            font-weight: 600;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .improvement-status.improved {
            background: var(--secure-bg);
            color: var(--success-green);
        }
        
        .improvement-status.maintained {
            background: #e6fffa;
            color: #2c7a7b;
        }
        
        .improvement-status.failed {
            background: var(--vulnerable-bg);
            color: var(--error-red);
        }
        
        .improvement-status.unknown {
            background: var(--neutral-bg);
            color: var(--text-light);
        }
        
        .technical-details {
            margin-top: 10px;
            font-size: 0.85rem;
            color: var(--text-light);
            font-family: 'Courier New', monospace;
        }
        
        /* CVSS Analysis */
        .cvss-analysis {
            background: var(--neutral-bg);
            padding: 20px;
            border-radius: 8px;
        }
        
        .cvss-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .cvss-metric {
            background: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid var(--border-light);
        }
        
        .metric-label {
            font-size: 0.9rem;
            color: var(--text-light);
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .metric-value {
            font-size: 2rem;
            font-weight: 700;
            color: var(--primary-navy);
        }
        
        .severity-High { color: var(--error-red); }
        .severity-Medium { color: var(--warning-orange); }
        .severity-Low { color: var(--success-green); }
        .severity-None { color: var(--text-light); }
        
        .vulnerability-list {
            background: white;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid var(--warning-orange);
        }
        
        .vulnerability-list h4 {
            margin: 0 0 10px 0;
            color: var(--primary-navy);
        }
        
        .vulnerability-list ul {
            margin: 0;
            padding-left: 20px;
        }
        
        /* Hardening Analysis */
        .hardening-analysis {
            background: var(--neutral-bg);
            padding: 20px;
            border-radius: 8px;
        }
        
        .hardening-measure {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: white;
            padding: 15px 20px;
            margin: 10px 0;
            border-radius: 8px;
            border: 1px solid var(--border-light);
        }
        
        .measure-name {
            font-weight: 600;
            color: var(--primary-navy);
        }
        
        .measure-status {
            padding: 6px 12px;
            border-radius: 4px;
            font-weight: 600;
            font-size: 0.8rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .measure-status.improved {
            background: var(--secure-bg);
            color: var(--success-green);
        }
        
        .measure-status.maintained {
            background: #e6fffa;
            color: #2c7a7b;
        }
        
        .measure-status.failed {
            background: var(--vulnerable-bg);
            color: var(--error-red);
        }
        
        .measure-status.unknown {
            background: var(--neutral-bg);
            color: var(--text-light);
        }
        
        .effectiveness-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        
        .effectiveness-metric {
            background: white;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid var(--border-light);
        }
        
        .overall-assessment {
            margin-top: 20px;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .overall-assessment.excellent {
            background: var(--secure-bg);
            color: var(--success-green);
            border: 2px solid #9ae6b4;
        }
        
        .overall-assessment.good {
            background: #e6fffa;
            color: #2c7a7b;
            border: 2px solid #81e6d9;
        }
        
        .overall-assessment.satisfactory {
            background: #fef5e7;
            color: var(--warning-orange);
            border: 2px solid #fbd38d;
        }
        
        .overall-assessment.baseline {
            background: var(--neutral-bg);
            color: var(--text-dark);
            border: 2px solid var(--border-light);
        }
        
        .overall-assessment.insufficient {
            background: var(--vulnerable-bg);
            color: var(--error-red);
            border: 2px solid #fed7d7;
        }
        
        /* Metrics Table */
        .metrics-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .metrics-table th {
            background: var(--primary-navy);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-size: 0.9rem;
        }
        
        .metrics-table td {
            padding: 15px;
            border-bottom: 1px solid var(--border-light);
        }
        
        .metrics-table tr:last-child td {
            border-bottom: none;
        }
        
        .metrics-table tr:nth-child(even) {
            background: var(--background-gray);
        }
        
        .change-positive { color: var(--success-green); font-weight: 600; }
        .change-negative { color: var(--error-red); font-weight: 600; }
        .change-neutral { color: var(--text-light); }
        
        /* Score Display */
        .security-score {
            text-align: center;
            padding: 30px;
            background: linear-gradient(135deg, var(--primary-navy) 0%, var(--primary-blue) 100%);
            color: white;
            margin: 20px 0;
        }
        
        .score-value {
            font-size: 4rem;
            font-weight: 300;
            margin: 0;
        }
        
        .score-label {
            font-size: 1.2rem;
            opacity: 0.9;
            margin: 10px 0 0 0;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        /* Analysis Content */
        .analysis-content {
            font-family: 'Courier New', monospace;
            font-size: 0.85rem;
            line-height: 1.4;
            max-height: 300px;
            overflow-y: auto;
            background: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            border: 1px solid var(--border-light);
        }
        
        /* Collapsible Sections */
        .collapsible {
            background: white;
            border: 1px solid var(--border-light);
            border-radius: 8px;
            margin: 20px 0;
        }
        
        .collapsible-header {
            padding: 20px;
            cursor: pointer;
            user-select: none;
            font-weight: 600;
            background: var(--background-gray);
            border-bottom: 1px solid var(--border-light);
            color: var(--primary-navy);
        }
        
        .collapsible-header:hover {
            background: #edf2f7;
        }
        
        .collapsible-content {
            padding: 20px;
            display: none;
        }
        
        .collapsible.active .collapsible-content {
            display: block;
        }
        
        pre {
            background: var(--primary-navy);
            color: #e2e8f0;
            padding: 15px;
            border-radius: 4px;
            overflow-x: auto;
            font-size: 0.8rem;
            line-height: 1.4;
            margin: 10px 0;
        }
        
        .footer {
            text-align: center;
            padding: 30px;
            color: var(--text-light);
            font-size: 0.9rem;
            background: var(--background-gray);
        }
        
        @media (max-width: 768px) {
            .comparison-chart {
                grid-template-columns: 1fr;
            }
            
            .comparison-arrow {
                display: none;
            }
            
            .cvss-summary,
            .effectiveness-summary {
                grid-template-columns: 1fr 1fr;
            }
        }
    </style>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const collapsibles = document.querySelectorAll('.collapsible-header');
            collapsibles.forEach(header => {
                header.addEventListener('click', function() {
                    this.parentElement.classList.toggle('active');
                });
            });
        });
    </script>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>Security Assessment Report</h1>
            <div class="subtitle">
                Experiment ID: <strong>$RUN_ID</strong> | 
                Generated: <strong>$GENERATED_AT</strong>
            </div>
        </div>

        <!-- Executive Summary -->
        <div class="content-section">
            <h2 class="section-title">Executive Summary</h2>
            
            <div class="security-score">
                <div class="score-value">$security_score</div>
                <div class="score-label">Security Score / 100</div>
            </div>
            
            <div class="comparison-chart">
                <div class="comparison-side before">
                    <div class="side-title before">Before Hardening</div>
                    <div class="analysis-content">
                        $BEFORE_CONTENT_HTML
                    </div>
                </div>
                
                <div class="comparison-arrow">→</div>
                
                <div class="comparison-side after">
                    <div class="side-title after">After Hardening</div>
                    <div class="analysis-content">
                        $AFTER_CONTENT_HTML
                    </div>
                </div>
            </div>
        </div>

        <!-- Attack Vector Analysis -->
        <div class="content-section">
            <h2 class="section-title">Attack Vector Analysis</h2>
            $ATTACK_RESULTS_HTML
        </div>

        <!-- Risk Assessment -->
        <div class="content-section">
            <h2 class="section-title">Risk Assessment</h2>
            $CVSS_SCORES_HTML
        </div>

        <!-- Security Hardening Assessment -->
        <div class="content-section">
            <h2 class="section-title">Security Hardening Assessment</h2>
            $HARDENING_EFFECTIVENESS_HTML
        </div>

        <!-- Detailed Metrics -->
        <div class="content-section">
            <h2 class="section-title">Detailed Security Metrics</h2>
            
            <table class="metrics-table">
                <thead>
                    <tr>
                        <th>Metric</th>
                        <th>Before</th>
                        <th>After</th>
                        <th>Change</th>
                        <th>Security Impact</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td><strong>Total Packets</strong></td>
                        <td>$before_packets</td>
                        <td>$after_packets</td>
                        <td class="$([ $packet_diff -gt 0 ] && echo 'change-positive' || [ $packet_diff -lt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $(if [ $packet_diff -gt 0 ]; then echo "-$packet_diff"; elif [ $packet_diff -lt 0 ]; then echo "+$((-packet_diff))"; else echo "0"; fi)
                        </td>
                        <td>Network Efficiency</td>
                    </tr>
                    <tr>
                        <td><strong>SMTP Commands</strong></td>
                        <td>$BEFORE_SMTP_CMDS_COUNT</td>
                        <td>$AFTER_SMTP_CMDS_COUNT</td>
                        <td class="$([ $cmd_decrease -gt 0 ] && echo 'change-positive' || echo 'change-neutral')">
                            $([ $cmd_decrease -gt 0 ] && echo "-$cmd_decrease" || echo "$(( AFTER_SMTP_CMDS_COUNT - BEFORE_SMTP_CMDS_COUNT ))")
                        </td>
                        <td>Attack Vector Reduction</td>
                    </tr>
                    <tr>
                        <td><strong>5xx Rejections</strong></td>
                        <td>$BEFORE_REJECT_COUNT</td>
                        <td>$AFTER_REJECT_COUNT</td>
                        <td class="$([ $reject_increase -gt 0 ] && echo 'change-positive' || echo 'change-neutral')">
                            $([ $reject_increase -gt 0 ] && echo "+$reject_increase" || echo "$reject_increase")
                        </td>
                        <td>Access Control Enforcement</td>
                    </tr>
                    <tr>
                        <td><strong>DATA Commands</strong></td>
                        <td>$BEFORE_DATA_ATTEMPTS</td>
                        <td>$AFTER_DATA_ATTEMPTS</td>
                        <td class="$([ $data_cmd_decrease -gt 0 ] && echo 'change-positive' || echo 'change-neutral')">
                            $([ $data_cmd_decrease -gt 0 ] && echo "-$data_cmd_decrease" || echo "$(( AFTER_DATA_ATTEMPTS - BEFORE_DATA_ATTEMPTS ))")
                        </td>
                        <td>Mail Relay Prevention</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <!-- Technical Details -->
        <div class="collapsible">
            <div class="collapsible-header">
                Technical Implementation Details
            </div>
            <div class="collapsible-content">
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 30px;">
                    <div>
                        <h4>Environment Information</h4>
                        $ENVIRONMENT_INFO_HTML
                    </div>
                    <div>
                        <h4>Generated Artifacts</h4>
                        $EXPERIMENT_ARTIFACTS_HTML
                    </div>
                </div>
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                Configuration Diff Analysis
            </div>
            <div class="collapsible-content">
                <p>Detailed comparison between pre-hardening and post-hardening configurations:</p>
                $DIFF_CONTENT_HTML
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                Assessment Methodology
            </div>
            <div class="collapsible-content">
                <h4>Security Score Calculation</h4>
                <ul>
                    <li><strong>70-100 Points:</strong> Comprehensive security hardening with multiple layers of protection</li>
                    <li><strong>40-69 Points:</strong> Significant security improvements with key vulnerabilities addressed</li>
                    <li><strong>20-39 Points:</strong> Partial security enhancements requiring additional measures</li>
                    <li><strong>0-19 Points:</strong> Minimal security improvement with ongoing vulnerabilities</li>
                </ul>
                
                <h4>Analysis Criteria</h4>
                <ul>
                    <li><strong>Attack Vector Mitigation:</strong> Reduction in successful attack attempts</li>
                    <li><strong>Response Code Analysis:</strong> Increase in security-positive 5xx responses</li>
                    <li><strong>Protocol Compliance:</strong> Enforcement of secure communication standards</li>
                    <li><strong>Configuration Hardening:</strong> Implementation of security best practices</li>
                </ul>
            </div>
        </div>

        <div class="footer">
            <p>Security Assessment Report | Generated by SMTP/DNS Vulnerability Assessment Lab<br>
            <strong>Professional Security Analysis Framework</strong></p>
        </div>
    </div>
</body>
</html>
EOF

echo "INFO: Professional security assessment report generated: $REPORT_FILE"
xdg-open "$REPORT_FILE" 2>/dev/null || open "$REPORT_FILE" 2>/dev/null || echo "INFO: Open $REPORT_FILE in your browser"

exit 0