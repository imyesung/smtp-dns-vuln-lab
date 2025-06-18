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
ARTIFACTS_DIR="$4" # 호스트 경로 기준

REPORT_FILE="${ARTIFACTS_DIR}/security_report_${RUN_ID}.html"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 공격 스크립트 실행 결과 수집 함수 (수정된 버전 - Hardening Effectiveness와 동일한 로직 사용)
collect_attack_results() {
    local attack_results=""
    local before_suffix="_BEFORE"
    local after_suffix="_AFTER"
    
    attack_results+="<h4>Attack Script Execution Results</h4>"
    
    # 디버깅 정보 추가
    attack_results+="<div style='font-size:0.75rem; color:#666; margin-bottom:8px;'>"
    attack_results+="디버깅: RUN_ID=$RUN_ID, 검색 패턴: *${RUN_ID}*${before_suffix}*, *${RUN_ID}*${after_suffix}*"
    attack_results+="</div>"
    
    # 1. Open Relay 공격 결과 (Hardening Effectiveness와 완전히 동일한 로직)
    local relay_before=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    local relay_after=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    attack_results+="<div class='attack-result'>"
    attack_results+="<strong>Open Relay Attack:</strong><br>"
    attack_results+="<span style='font-size:0.7rem; color:#888;'>찾는 파일: openrelay_${RUN_ID}_*.log</span><br>"
    
    if [ -f "$relay_before" ] || [ -f "$relay_after" ]; then
        local before_status="❓ 미테스트"
        local after_status="❓ 미테스트"
        
        # **Hardening Effectiveness와 동일한 분석 변수 사용**
        local before_success=0
        local after_success=0
        local before_blocked=0
        local after_blocked=0
        
        if [ -f "$relay_before" ]; then
            attack_results+="<span style='font-size:0.7rem; color:#888;'>Before 파일: $(basename "$relay_before")</span><br>"
            
            before_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_before" 2>/dev/null || echo "0")
            before_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_before" 2>/dev/null || echo "0")
            
            # **동일한 판단 로직 적용**
            if [ "$before_success" -gt 0 ]; then
                before_status="🔴 릴레이 허용"
            elif [ "$before_blocked" -gt 0 ]; then
                before_status="🟢 릴레이 차단"
            else
                # 로그 내용 일부 표시 (디버깅용)
                local sample_content=$(head -3 "$relay_before" | tr '\n' ' ' | cut -c1-100)
                attack_results+="<span style='font-size:0.6rem; color:#999;'>샘플: $sample_content...</span><br>"
            fi
        fi
        
        if [ -f "$relay_after" ]; then
            attack_results+="<span style='font-size:0.7rem; color:#888;'>After 파일: $(basename "$relay_after")</span><br>"
            
            after_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_after" 2>/dev/null || echo "0")
            after_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_after" 2>/dev/null || echo "0")
            
            # **동일한 판단 로직 적용**
            if [ "$after_success" -gt 0 ]; then
                after_status="🔴 릴레이 허용"
            elif [ "$after_blocked" -gt 0 ]; then
                after_status="🟢 릴레이 차단"
            fi
        fi
        
        attack_results+="&nbsp;&nbsp;Before: $before_status | After: $after_status"
        
        # **Hardening Effectiveness와 완전히 동일한 개선 상태 판단**
        if [ "$before_success" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            attack_results+=" <span style='color:green; font-weight:bold;'>(✅ 보안 강화됨)</span>"
        elif [ "$before_blocked" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            attack_results+=" <span style='color:blue; font-weight:bold;'>(✅ 이미 안전)</span>"
        elif [ "$before_success" -gt 0 ] && [ "$after_success" -gt 0 ]; then
            attack_results+=" <span style='color:red; font-weight:bold;'>(❌ 여전히 취약)</span>"
        elif [[ "$before_status" == "❓ 미테스트" || "$after_status" == "❓ 미테스트" ]]; then
            attack_results+=" <span style='color:orange; font-weight:bold;'>(⚠️ 분석 불가)</span>"
        fi
        
        # 디버깅 정보 추가 (Hardening Effectiveness와 동일)
        attack_results+="<br><span style='font-size:0.6rem; color:#999;'>디버깅: before_success=$before_success, before_blocked=$before_blocked, after_success=$after_success, after_blocked=$after_blocked</span>"
        
    else
        attack_results+="&nbsp;&nbsp;<span style='color:orange;'>⚠️ 테스트 로그 파일을 찾을 수 없음</span><br>"
        
        # 사용 가능한 파일 목록 표시 (디버깅)
        local available_files=$(ls "${ARTIFACTS_DIR}"/*${RUN_ID}* 2>/dev/null | grep -E "(openrelay|relay)" | head -3)
        if [ -n "$available_files" ]; then
            attack_results+="<span style='font-size:0.7rem; color:#888;'>사용 가능한 파일: $available_files</span>"
        fi
    fi
    attack_results+="</div>"
    
    # 2. STARTTLS 다운그레이드 공격 결과 (기존 코드 유지하되 파일 찾기 로직 개선)
    local starttls_before="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_BEFORE.txt"
    local starttls_after="${ARTIFACTS_DIR}/starttls_summary_${RUN_ID}_AFTER.txt"
    
    # 파일이 없으면 다른 패턴으로 검색
    if [ ! -f "$starttls_before" ]; then
        starttls_before=$(ls "${ARTIFACTS_DIR}"/*starttls*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    fi
    if [ ! -f "$starttls_after" ]; then
        starttls_after=$(ls "${ARTIFACTS_DIR}"/*starttls*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    fi
    
    attack_results+="<div class='attack-result'>"
    attack_results+="<strong>STARTTLS Downgrade Attack:</strong><br>"
    
    if [ -f "$starttls_before" ] || [ -f "$starttls_after" ]; then
        local before_vuln="❓ 미테스트"
        local after_vuln="❓ 미테스트"
        
        if [ -f "$starttls_before" ]; then
            if grep -q "VULNERABLE\|HIGHLY VULNERABLE" "$starttls_before" 2>/dev/null; then
                before_vuln="🔴 취약"
            elif grep -q "SECURE" "$starttls_before" 2>/dev/null; then
                before_vuln="🟢 안전"
            fi
        fi
        
        if [ -f "$starttls_after" ]; then
            if grep -q "VULNERABLE\|HIGHLY VULNERABLE" "$starttls_after" 2>/dev/null; then
                after_vuln="🔴 취약"
            elif grep -q "SECURE" "$starttls_after" 2>/dev/null; then
                after_vuln="🟢 안전"
            fi
        fi
        
        attack_results+="&nbsp;&nbsp;Before: $before_vuln | After: $after_vuln"
        
        if [[ "$before_vuln" == "🔴 취약" && "$after_vuln" == "🟢 안전" ]]; then
            attack_results+=" <span style='color:green; font-weight:bold;'>(✅ 개선됨)</span>"
        elif [[ "$before_vuln" == "$after_vuln" && "$before_vuln" == "🔴 취약" ]]; then
            attack_results+=" <span style='color:red; font-weight:bold;'>(❌ 여전히 취약)</span>"
        elif [[ "$before_vuln" == "🟢 안전" && "$after_vuln" == "🟢 안전" ]]; then
            attack_results+=" <span style='color:blue; font-weight:bold;'>(✅ 이미 안전)</span>"
        fi
    else
        attack_results+="&nbsp;&nbsp;<span style='color:orange;'>⚠️ 테스트 결과 없음</span>"
    fi
    attack_results+="</div>"
    
    # 3. 평문 인증 공격 결과 (개선된 파일 찾기)
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
    
    attack_results+="<div class='attack-result'>"
    attack_results+="<strong>Plaintext Authentication Attack:</strong><br>"
    
    if [ -f "$auth_before" ] || [ -f "$auth_after" ]; then
        local before_auth="❓ 미테스트"
        local after_auth="❓ 미테스트"
        
        if [ -f "$auth_before" ]; then
            if grep -q "HIGHLY VULNERABLE\|VULNERABLE\|235.*Authentication successful\|평문.*허용" "$auth_before" 2>/dev/null; then
                before_auth="🔴 평문 허용"
            elif grep -q "SECURE\|530.*TLS.*required\|TLS.*필수" "$auth_before" 2>/dev/null; then
                before_auth="🟢 TLS 필수"
            fi
        fi
        
        if [ -f "$auth_after" ]; then
            if grep -q "HIGHLY VULNERABLE\|VULNERABLE\|235.*Authentication successful\|평문.*허용" "$auth_after" 2>/dev/null; then
                after_auth="🔴 평문 허용"
            elif grep -q "SECURE\|530.*TLS.*required\|TLS.*필수" "$auth_after" 2>/dev/null; then
                after_auth="🟢 TLS 필수"
            fi
        fi
        
        attack_results+="&nbsp;&nbsp;Before: $before_auth | After: $after_auth"
        
        if [[ "$before_auth" == "🔴 평문 허용" && "$after_auth" == "🟢 TLS 필수" ]]; then
            attack_results+=" <span style='color:green; font-weight:bold;'>(✅ TLS 강제 적용)</span>"
        elif [[ "$before_auth" == "🟢 TLS 필수" && "$after_auth" == "🟢 TLS 필수" ]]; then
            attack_results+=" <span style='color:blue; font-weight:bold;'>(✅ 이미 안전)</span>"
        fi
    else
        attack_results+="&nbsp;&nbsp;<span style='color:orange;'>⚠️ 테스트 결과 없음</span>"
    fi
    attack_results+="</div>"
    
    # 4-6. 나머지 테스트들 (기존 로직 유지하되 "이미 안전" 케이스 추가)
    # ...existing code for DNS, DANE, SPF/DKIM/DMARC...
    
    echo "$attack_results"
}

# CVSS 점수 수집 함수 (수정된 버전 - 실제 하드닝 효과 반영)
collect_cvss_scores() {
    local cvss_results=""
    
    cvss_results+="<h4>CVSS 3.1 Risk Assessment</h4>"
    
    local vulnerabilities_found=()
    local total_cvss_score=0.0
    local max_severity="None"
    
    # 실제로 존재하는 파일들을 먼저 확인
    local available_files=$(ls "${ARTIFACTS_DIR}"/*${RUN_ID}* 2>/dev/null)
    cvss_results+="<div style='font-size:0.75rem; color:#666; margin-bottom:8px;'>"
    cvss_results+="검색된 파일: $(echo "$available_files" | wc -l)개"
    cvss_results+="</div>"
    
    # Open Relay 취약점 확인 (수정된 로직 - AFTER 파일 기준으로 판단)
    local relay_vuln_found=false
    local relay_after_file=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    if [ -f "$relay_after_file" ]; then
        # **AFTER 파일에서 SUCCESS가 있으면 여전히 취약**
        local after_success_count=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|250.*Message.*accepted' "$relay_after_file" 2>/dev/null || echo "0")
        if [ "$after_success_count" -gt 0 ]; then
            relay_vuln_found=true
            cvss_results+="<div style='font-size:0.75rem; color:#666;'>Open Relay 취약점 감지됨 (AFTER 파일에서 SUCCESS 발견)</div>"
        else
            cvss_results+="<div style='font-size:0.75rem; color:#666;'>Open Relay 취약점 해결됨 (AFTER 파일에서 SUCCESS 없음)</div>"
        fi
    else
        # AFTER 파일이 없으면 BEFORE 파일로 대체 판단
        for relay_file in $(find "$ARTIFACTS_DIR" -name "*relay*${RUN_ID}*" -type f 2>/dev/null); do
            local success_count=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|250.*Message.*accepted' "$relay_file" 2>/dev/null || echo "0")
            if [ "$success_count" -gt 0 ]; then
                relay_vuln_found=true
                cvss_results+="<div style='font-size:0.75rem; color:#666;'>Open Relay 취약점 감지됨 (일반 파일에서 SUCCESS 발견)</div>"
                break
            fi
        done
    fi
    
    if [ "$relay_vuln_found" = true ]; then
        vulnerabilities_found+=("open_relay")
        total_cvss_score=$(echo "$total_cvss_score + 7.5" | bc -l 2>/dev/null || echo "7.5")
        max_severity="High"
        cvss_results+="<div style='font-size:0.75rem; color:#666;'>Open Relay 취약점 감지됨</div>"
    else
        cvss_results+="<div style='font-size:0.75rem; color:#666;'>Open Relay 취약점 없음</div>"
    fi
    
    # STARTTLS 다운그레이드 취약점 확인
    if find "$ARTIFACTS_DIR" -name "*starttls*${RUN_ID}*" -type f -exec grep -l "VULNERABLE\|HIGHLY VULNERABLE" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("starttls_downgrade")
        total_cvss_score=$(echo "$total_cvss_score + 8.1" | bc -l 2>/dev/null || echo "$total_cvss_score")
        max_severity="High"
    fi
    
    # 평문 인증 취약점 확인 (패턴 확장)
    if find "$ARTIFACTS_DIR" -name "*auth*${RUN_ID}*" -o -name "*plaintext*${RUN_ID}*" -type f -exec grep -l "HIGHLY VULNERABLE\|235.*successful" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("plaintext_auth")
        total_cvss_score=$(echo "$total_cvss_score + 7.8" | bc -l 2>/dev/null || echo "$total_cvss_score")
        max_severity="High"
    fi
    
    # DNS 재귀 취약점 확인
    if find "$ARTIFACTS_DIR" -name "*dns*${RUN_ID}*" -type f -exec grep -l "VULNERABLE.*recursion\|재귀.*허용" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("dns_recursion")
        total_cvss_score=$(echo "$total_cvss_score + 5.3" | bc -l 2>/dev/null || echo "$total_cvss_score")
        if [ "$max_severity" = "None" ]; then max_severity="Medium"; fi
    fi
    
    # SPF/DKIM/DMARC 취약점 확인
    if find "$ARTIFACTS_DIR" -name "*spf*${RUN_ID}*" -o -name "*dmarc*${RUN_ID}*" -type f -exec grep -l "VULNERABLE\|spoofing.*SUCCESS\|스푸핑.*가능" {} \; 2>/dev/null | grep -q .; then
        vulnerabilities_found+=("email_spoofing")
        total_cvss_score=$(echo "$total_cvss_score + 6.2" | bc -l 2>/dev/null || echo "$total_cvss_score")
        if [ "$max_severity" = "None" ]; then max_severity="Medium"; fi
    fi
    
    # 평균 CVSS 점수 계산
    local avg_cvss_score=0.0
    if [ ${#vulnerabilities_found[@]} -gt 0 ]; then
        avg_cvss_score=$(echo "scale=1; $total_cvss_score / ${#vulnerabilities_found[@]}" | bc -l 2>/dev/null || echo "0.0")
    fi
    
    cvss_results+="<div class='cvss-scores'>"
    cvss_results+="<div class='cvss-score'><strong>발견된 취약점:</strong> ${#vulnerabilities_found[@]}개</div>"
    cvss_results+="<div class='cvss-score'><strong>평균 CVSS 점수:</strong> $avg_cvss_score</div>"
    cvss_results+="<div class='cvss-score'><strong>총합 점수:</strong> $total_cvss_score</div>"
    cvss_results+="<div class='cvss-severity'><strong>최고 위험도:</strong> "
    
    case "$max_severity" in
        "Critical") cvss_results+="<span style='color:darkred; font-weight:bold;'>🔴 CRITICAL</span>" ;;
        "High") cvss_results+="<span style='color:red; font-weight:bold;'>🟠 HIGH</span>" ;;
        "Medium") cvss_results+="<span style='color:orange; font-weight:bold;'>🟡 MEDIUM</span>" ;;
        "Low") cvss_results+="<span style='color:green; font-weight:bold;'>🟢 LOW</span>" ;;
        *) cvss_results+="<span style='color:gray;'>❓ None</span>" ;;
    esac
    cvss_results+="</div></div>"
    
    # 자동 계산 결과 표시
    if [ ${#vulnerabilities_found[@]} -gt 0 ]; then
        cvss_results+="<div style='margin-top:12px; font-size:0.875rem;'>"
        cvss_results+="<strong>감지된 취약점:</strong><br>"
        for vuln in "${vulnerabilities_found[@]}"; do
            cvss_results+="• $vuln 취약점<br>"
        done
        cvss_results+="</div>"
    else
        cvss_results+="<div style='margin-top:12px; font-size:0.875rem; color:#666;'>"
        cvss_results+="<strong>참고:</strong> 자동화된 스크립트 실행 결과에서 취약점이 감지되지 않았습니다.<br>"
        cvss_results+="수동 분석이나 추가 테스트가 필요할 수 있습니다."
        cvss_results+="</div>"
    fi
    
    echo "$cvss_results"
}

# 하드닝 효과 분석 함수 (수정된 버전 - 일관된 분석 로직)
collect_hardening_effectiveness() {
    local hardening_results=""
    local before_suffix="_${RUN_ID}_BEFORE"
    local after_suffix="_${RUN_ID}_AFTER"
    
    hardening_results+="<h4>Security Hardening Effectiveness</h4>"
    
    local improvements=0
    local already_secure=0
    local total_tests=0
    local detailed_analysis=""
    
    # Open Relay 개선 확인 (Attack Results와 동일한 로직 사용)
    local relay_before=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*BEFORE* 2>/dev/null | head -1)
    local relay_after=$(ls "${ARTIFACTS_DIR}"/*relay*${RUN_ID}*AFTER* 2>/dev/null | head -1)
    
    if [ -f "$relay_before" ] && [ -f "$relay_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='measure'><strong>Open Relay 테스트:</strong> "
        
        local before_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_before" 2>/dev/null || echo "0")
        local after_success=$(grep -c '"result_status".*"SUCCESS"\|250.*Ok\|메일.*성공' "$relay_after" 2>/dev/null || echo "0")
        local before_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_before" 2>/dev/null || echo "0")
        local after_blocked=$(grep -c '"result_status".*"BLOCKED"\|550\|554\|거부\|차단' "$relay_after" 2>/dev/null || echo "0")
        
        # 디버깅 정보 추가
        detailed_analysis+="<span style='font-size:0.7rem; color:#888;'>[디버깅: B_success=$before_success, B_blocked=$before_blocked, A_success=$after_success, A_blocked=$after_blocked]</span> "
        
        if [ "$before_success" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            detailed_analysis+="✅ 개선됨 (취약 → 차단)"
            improvements=$((improvements + 1))
        elif [ "$before_blocked" -gt 0 ] && [ "$after_blocked" -gt 0 ]; then
            detailed_analysis+="✅ 이미 안전 (차단 유지)"
            already_secure=$((already_secure + 1))
        elif [ "$before_success" -gt 0 ] && [ "$after_success" -gt 0 ]; then
            detailed_analysis+="❌ 여전히 취약 (릴레이 허용)"
        else
            detailed_analysis+="⚠️ 결과 불분명 (before_success=$before_success, before_blocked=$before_blocked, after_success=$after_success, after_blocked=$after_blocked)"
        fi
        detailed_analysis+="</div>"
    fi
    
    # STARTTLS 개선 확인
    local starttls_before="${ARTIFACTS_DIR}/starttls_summary${before_suffix}.txt"
    local starttls_after="${ARTIFACTS_DIR}/starttls_summary${after_suffix}.txt"
    
    if [ -f "$starttls_before" ] && [ -f "$starttls_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='measure'><strong>STARTTLS 보안:</strong> "
        
        local before_vuln=$(grep -c "VULNERABLE" "$starttls_before" 2>/dev/null || echo "0")
        local after_secure=$(grep -c "SECURE" "$starttls_after" 2>/dev/null || echo "0")
        
        if [ "$before_vuln" -gt 0 ] && [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 개선됨 (취약 → 안전)"
            improvements=$((improvements + 1))
        elif [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 유지됨 (보안 지속)"
            already_secure=$((already_secure + 1))
        else
            detailed_analysis+="❌ 개선 안됨"
        fi
        detailed_analysis+="</div>"
    fi
    
    # 평문 인증 개선 확인
    local auth_before="${ARTIFACTS_DIR}/auth_plain_summary${before_suffix}.txt"
    local auth_after="${ARTIFACTS_DIR}/auth_plain_summary${after_suffix}.txt"
    
    if [ -f "$auth_before" ] && [ -f "$auth_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='measure'><strong>인증 보안:</strong> "
        
        local before_vuln=$(grep -c "VULNERABLE" "$auth_before" 2>/dev/null || echo "0")
        local after_secure=$(grep -c "SECURE" "$auth_after" 2>/dev/null || echo "0")
        
        if [ "$before_vuln" -gt 0 ] && [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 개선됨 (평문 허용 → TLS 필수)"
            improvements=$((improvements + 1))
        elif [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 유지됨 (TLS 지속)"
            already_secure=$((already_secure + 1))
        else
            detailed_analysis+="❌ 개선 안됨"
        fi
        detailed_analysis+="</div>"
    fi
    
    # DNS 보안 개선 확인
    local dns_before="${ARTIFACTS_DIR}/dns_recursion_summary${before_suffix}.txt"
    local dns_after="${ARTIFACTS_DIR}/dns_recursion_summary${after_suffix}.txt"
    
    if [ -f "$dns_before" ] && [ -f "$dns_after" ]; then
        total_tests=$((total_tests + 1))
        detailed_analysis+="<div class='measure'><strong>DNS 재귀 보안:</strong> "
        
        local before_vuln=$(grep -c "VULNERABLE" "$dns_before" 2>/dev/null || echo "0")
        local after_secure=$(grep -c "SECURE" "$dns_after" 2>/dev/null || echo "0")
        
        if [ "$before_vuln" -gt 0 ] && [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 개선됨 (재귀 허용 → 제한)"
            improvements=$((improvements + 1))
        elif [ "$after_secure" -gt 0 ]; then
            detailed_analysis+="✅ 유지됨 (제한 지속)"
            already_secure=$((already_secure + 1))
        else
            detailed_analysis+="❌ 개선 안됨"
        fi
        detailed_analysis+="</div>"
    fi
    
    hardening_results+="<div class='hardening-measures'>"
    hardening_results+="$detailed_analysis"
    hardening_results+="</div>"
    
    # 종합 하드닝 효과 평가 (수정된 계산)
    local effectiveness_percentage=0
    local total_security_actions=$((improvements + already_secure))
    
    if [ "$total_tests" -gt 0 ]; then
        effectiveness_percentage=$(( (total_security_actions * 100) / total_tests ))
    fi
    
    hardening_results+="<div class='hardening-status "
    
    if [ "$effectiveness_percentage" -ge 75 ]; then
        if [ "$improvements" -gt "$already_secure" ]; then
            hardening_results+="success'>🛡️ <strong>강력한 보안 강화</strong> (신규 ${improvements}개, 기존 ${already_secure}개, ${effectiveness_percentage}% 효과)</div>"
        else
            hardening_results+="success'>✅ <strong>이미 안전한 상태</strong> (기존 ${already_secure}개, 신규 ${improvements}개, ${effectiveness_percentage}% 보안)</div>"
        fi
    elif [ "$effectiveness_percentage" -ge 50 ]; then
        hardening_results+="partial'>⚠️ <strong>부분적 보안 강화</strong> (${improvements}개 개선, ${already_secure}개 유지, ${effectiveness_percentage}% 효과)</div>"
    elif [ "$already_secure" -gt 0 ]; then
        hardening_results+="partial'>🔶 <strong>기본 보안 유지</strong> (${already_secure}개 항목 이미 안전, ${improvements}개 신규 개선)</div>"
    else
        hardening_results+="warning'>❌ <strong>보안 강화 효과 제한적</strong> (${improvements}개 개선, ${total_tests}개 테스트)</div>"
    fi
    
    echo "$hardening_results"
}

BEFORE_CONTENT_HTML=$(format_analysis_content "$BEFORE_ANALYSIS_FILE")
AFTER_CONTENT_HTML=$(format_analysis_content "$AFTER_ANALYSIS_FILE")

# 실험 결과 수집 (Git 정보 제거)
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
<html lang="ko">
<head>
    <meta charset="utf-8">
    <title>SMTP/DNS 취약점 분석 보고서 - $RUN_ID</title>
    <style>
        :root {
            --primary-dark: #2d3748;
            --primary-light: #f7fafc;
            --accent-blue: #4299e1;
            --accent-teal: #38b2ac;
            --success-green: #48bb78;
            --warning-orange: #ed8936;
            --error-red: #f56565;
            --text-dark: #2d3748;
            --text-light: #718096;
            --border-light: #e2e8f0;
            --shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        }
        
        * { box-sizing: border-box; }
        
        body { 
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            margin: 0; 
            padding: 16px; 
            background: linear-gradient(135deg, var(--primary-light) 0%, #edf2f7 100%);
            color: var(--text-dark); 
            line-height: 1.5; 
            min-height: 100vh;
        }
        
        .container { 
            max-width: 1400px; 
            margin: 0 auto; 
            display: grid; 
            gap: 16px; 
            grid-template-columns: 1fr;
            padding: 0 16px;
        }
        
        /* 실험 타임라인 스타일 추가 */
        .timeline {
            position: relative;
            margin: 20px 0;
        }
        
        .timeline::before {
            content: '';
            position: absolute;
            left: 20px;
            top: 0;
            bottom: 0;
            width: 2px;
            background: var(--accent-blue);
        }
        
        .timeline-item {
            position: relative;
            margin: 16px 0;
            padding-left: 50px;
        }
        
        .timeline-item::before {
            content: '';
            position: absolute;
            left: 14px;
            top: 8px;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: var(--accent-blue);
            border: 3px solid white;
            box-shadow: 0 0 0 2px var(--accent-blue);
        }
        
        .timeline-commit {
            background: white;
            padding: 12px;
            border-radius: 8px;
            border-left: 4px solid var(--accent-blue);
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .commit-hash {
            font-family: 'SF Mono', Monaco, monospace;
            background: var(--border-light);
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.875rem;
            color: var(--accent-blue);
        }
        
        .experiment-summary {
            background: white;
            border-radius: 12px;
            box-shadow: var(--shadow);
            border: 1px solid var(--border-light);
            margin: 16px 0;
        }
        
        .experiment-summary-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 12px 12px 0 0;
        }
        
        .experiment-summary-content {
            padding: 20px;
        }
        
        .artifact-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 16px;
            margin: 16px 0;
        }
        
        .artifact-card {
            background: var(--primary-light);
            padding: 16px;
            border-radius: 8px;
            border: 1px solid var(--border-light);
        }
        
        .artifact-card h4 {
            margin: 0 0 12px 0;
            color: var(--primary-dark);
            font-size: 1rem;
        }
        
        .artifact-card ul {
            margin: 0;
            padding-left: 20px;
            font-size: 0.875rem;
        }
        
        .artifact-card li {
            margin: 6px 0;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-dark) 0%, #4a5568 100%);
            color: white;
            padding: 24px;
            border-radius: 12px;
            text-align: center;
            box-shadow: var(--shadow);
        }
        
        .header h1 { 
            margin: 0 0 12px 0; 
            font-size: 2rem; 
            font-weight: 700; 
            letter-spacing: -0.025em;
        }
        
        .header .subtitle {
            font-size: 1.1rem;
            opacity: 0.9;
            font-weight: 400;
        }
        
        .experiment-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 16px;
            margin: 16px 0;
        }
        
        .experiment-card {
            background: white;
            border-radius: 12px;
            box-shadow: var(--shadow);
            overflow: hidden;
            border: 1px solid var(--border-light);
        }
        
        .experiment-header {
            padding: 20px;
            border-bottom: 1px solid var(--border-light);
        }
        
        .experiment-header.before {
            background: linear-gradient(135deg, #feb2b2 0%, #fed7d7 100%);
            color: #742a2a;
        }
        
        .experiment-header.after {
            background: linear-gradient(135deg, #9ae6b4 0%, #c6f6d5 100%);
            color: #22543d;
        }
        
        .experiment-header h3 {
            margin: 0 0 8px 0;
            font-size: 1.25rem;
            font-weight: 600;
        }
        
        .experiment-content {
            padding: 20px;
            max-height: 280px;
            overflow-y: auto;
            font-size: 0.8rem;
            line-height: 1.5;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
        }
        
        .experiment-content p {
            margin: 8px 0;
            word-wrap: break-word;
        }
        
        .experiment-content h4 {
            color: var(--accent-blue);
            margin: 12px 0 8px 0;
            font-size: 0.9rem;
            border-bottom: 1px solid var(--border-light);
            padding-bottom: 4px;
        }
        
        .experiment-content h5 {
            color: var(--text-dark);
            margin: 10px 0 6px 0;
            font-size: 0.85rem;
        }
        
        .experiment-content hr {
            border: none;
            border-top: 1px solid var(--border-light);
            margin: 12px 0;
        }
        
        .experiment-content strong {
            color: var(--primary-dark);
        }
        
        .verdict-section {
            background: white;
            border-radius: 12px;
            box-shadow: var(--shadow);
            overflow: hidden;
            border: 1px solid var(--border-light);
        }
        
        .verdict-header {
            background: linear-gradient(135deg, var(--accent-blue) 0%, var(--accent-teal) 100%);
            color: white;
            padding: 20px;
        }
        
        .verdict-header h2 {
            margin: 0;
            font-size: 1.5rem;
            font-weight: 600;
        }
        
        .verdict-content {
            padding: 20px;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
            margin: 20px 0;
        }
        
        .metric-card {
            background: var(--primary-light);
            padding: 16px;
            border-radius: 8px;
            text-align: center;
            border: 1px solid var(--border-light);
        }
        
        .metric-value {
            font-size: 2rem;
            font-weight: 700;
            margin: 8px 0;
        }
        
        .metric-label {
            font-size: 0.875rem;
            color: var(--text-light);
            font-weight: 500;
        }
        
        .metric-change {
            font-size: 0.875rem;
            margin-top: 4px;
            font-weight: 600;
        }
        
        .change-positive { color: var(--success-green); }
        .change-negative { color: var(--error-red); }
        .change-neutral { color: var(--text-light); }
        
        .status-badge {
            display: inline-flex;
            align-items: center;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.875rem;
            font-weight: 600;
            margin: 8px 0;
        }
        
        .status-success {
            background: #f0fff4;
            color: var(--success-green);
            border: 1px solid #9ae6b4;
        }
        
        .status-warning {
            background: #fffaf0;
            color: var(--warning-orange);
            border: 1px solid #fbd38d;
        }
        
        .status-error {
            background: #fff5f5;
            color: var(--error-red);
            border: 1px solid #feb2b2;
        }
        
        .analysis-table {
            width: 100%;
            border-collapse: collapse;
            margin: 16px 0;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
            font-size: 0.875rem;
        }
        
        .analysis-table th {
            background: var(--primary-dark);
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        
        .analysis-table td {
            padding: 12px;
            border-bottom: 1px solid var(--border-light);
        }
        
        .analysis-table tr:last-child td {
            border-bottom: none;
        }
        
        .analysis-table tr:nth-child(even) {
            background: var(--primary-light);
        }
        
        .score-display {
            text-align: center;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 12px;
            margin: 12px 0;
        }
        
        .score-value {
            font-size: 3rem;
            font-weight: 700;
            margin: 0;
        }
        
        .score-label {
            font-size: 1.25rem;
            opacity: 0.9;
            margin: 8px 0 0 0;
        }
        
        pre {
            background: var(--primary-dark);
            color: #e2e8f0;
            padding: 12px;
            border-radius: 6px;
            overflow-x: auto;
            font-size: 0.7rem;
            line-height: 1.3;
            border: 1px solid #4a5568;
            white-space: pre-wrap;
            word-wrap: break-word;
            max-height: 200px;
            overflow-y: auto;
            margin: 8px 0;
        }
        
        pre.json {
            background: #2d3748;
            color: #fbb6ce;
            border-color: #4a5568;
        }
        
        .collapsible {
            background: var(--primary-light);
            border: 1px solid var(--border-light);
            border-radius: 8px;
            margin: 16px 0;
        }
        
        .collapsible-header {
            padding: 16px 20px;
            cursor: pointer;
            user-select: none;
            font-weight: 600;
            background: white;
            border-radius: 8px 8px 0 0;
            border-bottom: 1px solid var(--border-light);
        }
        
        .collapsible-header:hover {
            background: var(--primary-light);
        }
        
        .collapsible-content {
            padding: 20px;
            display: none;
        }
        
        .collapsible.active .collapsible-content {
            display: block;
        }
        
        .footer {
            text-align: center;
            padding: 24px;
            color: var(--text-light);
            font-size: 0.875rem;
        }
        
        code {
            background: var(--border-light);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            font-size: 0.875rem;
        }
        
        /* 실험 결과 스타일 추가 */
        .attack-result {
            margin: 8px 0;
            padding: 8px 12px;
            background: var(--primary-light);
            border-radius: 6px;
            border-left: 4px solid var(--accent-blue);
            font-size: 0.875rem;
        }
        
        .cvss-scores {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 12px;
            margin: 12px 0;
        }
        
        .cvss-score {
            background: var(--primary-light);
            padding: 8px;
            border-radius: 6px;
            text-align: center;
            font-size: 0.875rem;
        }
        
        .cvss-severity {
            grid-column: 1 / -1;
            text-align: center;
            font-size: 1.1rem;
            margin-top: 8px;
        }
        
        .hardening-measures {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 8px;
            margin: 12px 0;
        }
        
        .measure {
            background: var(--primary-light);
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 0.875rem;
        }
        
        .hardening-status {
            margin: 16px 0;
            padding: 12px;
            border-radius: 8px;
            text-align: center;
            font-weight: bold;
        }
        
        .hardening-status.success {
            background: #f0fff4;
            color: var(--success-green);
            border: 1px solid #9ae6b4;
        }
        
        .hardening-status.partial {
            background: #fffaf0;
            color: var(--warning-orange);
            border: 1px solid #fbd38d;
        }
        
        .hardening-status.warning {
            background: #fff5f5;
            color: var(--error-red);
            border: 1px solid #feb2b2;
        }
        
        @media (max-width: 768px) {
            .experiment-grid {
                grid-template-columns: 1fr;
            }
            
            .metrics-grid {
                grid-template-columns: 1fr 1fr;
            }
            
            .header h1 {
                font-size: 2rem;
            }
            
            .score-value {
                font-size: 3rem;
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
        <!-- Header Section -->
        <div class="header">
            <h1>SMTP/DNS 취약점 분석 보고서</h1>
            <div class="subtitle">
                실행 ID: <strong>$RUN_ID</strong> | 
                생성 시간: <strong>$GENERATED_AT</strong>
            </div>
        </div>

        <!-- 실험 결과 요약 섹션 -->
        <div class="experiment-summary">
            <div class="experiment-summary-header">
                <h2>Security Assessment Results</h2>
            </div>
            <div class="experiment-summary-content">
                <div class="artifact-grid">
                    <div class="artifact-card">
                        $ATTACK_RESULTS_HTML
                    </div>
                    <div class="artifact-card">
                        $CVSS_SCORES_HTML
                    </div>
                </div>
                <div class="artifact-card" style="margin-top: 16px;">
                    $HARDENING_EFFECTIVENESS_HTML
                </div>
            </div>
        </div>

        <!-- Security Score Display -->
        <div class="score-display">
            <div class="score-value">$security_score</div>
            <div class="score-label">종합 보안 점수 / 100</div>
        </div>

        <!-- Main Verdict -->
        <div class="verdict-section">
            <div class="verdict-header">
                <h2>보안 강화 효과 분석</h2>
            </div>
            <div class="verdict-content">
                $VERDICT
                
                <!-- Key Metrics Grid -->
                <div class="metrics-grid">
                    <div class="metric-card">
                        <div class="metric-label">총 패킷 수</div>
                        <div class="metric-value">$before_packets → $after_packets</div>
                        <div class="metric-change $([ $packet_diff -gt 0 ] && echo 'change-positive' || [ $packet_diff -lt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $(if [ $packet_diff -gt 0 ]; then echo "-$packet_diff 패킷 (감소)"; elif [ $packet_diff -lt 0 ]; then echo "+$((-packet_diff)) 패킷 (증가)"; else echo '변화 없음'; fi)
                        </div>
                    </div>
                    
                    <div class="metric-card">
                        <div class="metric-label">SMTP 명령 수</div>
                        <div class="metric-value">$BEFORE_SMTP_CMDS_COUNT → $AFTER_SMTP_CMDS_COUNT</div>
                        <div class="metric-change $([ $cmd_decrease -gt 0 ] && echo 'change-positive' || [ $cmd_decrease -lt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $([ $cmd_decrease -eq 0 ] && echo '변화 없음' || [ $cmd_decrease -gt 0 ] && echo "-$cmd_decrease 명령" || echo "+$((AFTER_SMTP_CMDS_COUNT - BEFORE_SMTP_CMDS_COUNT)) 명령")
                        </div>
                    </div>
                    
                    <div class="metric-card">
                        <div class="metric-label">거부 응답 (5xx)</div>
                        <div class="metric-value">$BEFORE_REJECT_COUNT → $AFTER_REJECT_COUNT</div>
                        <div class="metric-change $([ $reject_increase -gt 0 ] && echo 'change-positive' || [ $reject_increase -lt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $([ $reject_increase -eq 0 ] && echo '변화 없음' || [ $reject_increase -gt 0 ] && echo "+$reject_increase 거부" || echo "$reject_increase 거부")
                        </div>
                    </div>
                    
                    <div class="metric-card">
                        <div class="metric-label">DATA 명령 차단</div>
                        <div class="metric-value">$BEFORE_DATA_ATTEMPTS → $AFTER_DATA_ATTEMPTS</div>
                        <div class="metric-change $([ $data_cmd_decrease -gt 0 ] && echo 'change-positive' || [ $data_cmd_decrease -lt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $([ $data_cmd_decrease -eq 0 ] && echo '변화 없음' || [ $data_cmd_decrease -gt 0 ] && echo "-$data_cmd_decrease 차단" || echo "+$((AFTER_DATA_ATTEMPTS - BEFORE_DATA_ATTEMPTS)) 시도")
                        </div>
                    </div>
                </div>

                <!-- Status Badge -->
                <div class="$([ $security_score -ge 70 ] && echo 'status-success' || [ $security_score -ge 40 ] && echo 'status-success' || [ $security_score -ge 20 ] && echo 'status-warning' || echo 'status-error') status-badge">
                    $([ $security_score -ge 70 ] && echo '🛡️ 강력한 보안 강화' || [ $security_score -ge 40 ] && echo '✅ 보안 강화 성공' || [ $security_score -ge 20 ] && echo '⚠️ 부분적 개선' || echo '❌ 강화 실패')
                </div>
            </div>
        </div>

        <!-- Traffic Analysis -->
        <div class="verdict-section">
            <div class="verdict-header">
                <h2>트래픽 패턴 분석</h2>
            </div>
            <div class="verdict-content">
                $PACKET_VERDICT
            </div>
        </div>

        <!-- Experiment Results Grid -->
        <div class="experiment-grid">
            <div class="experiment-card">
                <div class="experiment-header before">
                    <h3>강화 전 실험 결과</h3>
                    <code>$BEFORE_ANALYSIS_FILE</code>
                </div>
                <div class="experiment-content">
                    $BEFORE_CONTENT_HTML
                </div>
            </div>
            
            <div class="experiment-card">
                <div class="experiment-header after">
                    <h3>강화 후 실험 결과</h3>
                    <code>$AFTER_ANALYSIS_FILE</code>
                </div>
                <div class="experiment-content">
                    $AFTER_CONTENT_HTML
                </div>
            </div>
        </div>

        <!-- Detailed Analysis Table -->
        <div class="verdict-section">
            <div class="verdict-header">
                <h2>상세 분석 지표</h2>
            </div>
            <div class="verdict-content">
                <table class="analysis-table">
                    <thead>
                        <tr>
                            <th>지표</th>
                            <th>강화 전</th>
                            <th>강화 후</th>
                            <th>변화</th>
                            <th>보안 영향</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td><strong>총 패킷 수</strong></td>
                            <td>$before_packets</td>
                            <td>$after_packets</td>
                            <td style="color: $([ $packet_diff -gt 0 ] && echo 'var(--success-green)' || [ $packet_diff -lt 0 ] && echo 'var(--error-red)' || echo 'var(--text-light)');">
                                $(if [ $packet_diff -gt 0 ]; then echo "-$packet_diff"; elif [ $packet_diff -lt 0 ]; then echo "+$((-packet_diff))"; else echo "0"; fi)
                            </td>
                            <td>네트워크 효율성</td>
                        </tr>
                        <tr>
                            <td><strong>SMTP 명령 수</strong></td>
                            <td>$BEFORE_SMTP_CMDS_COUNT</td>
                            <td>$AFTER_SMTP_CMDS_COUNT</td>
                            <td style="color: $([ $cmd_decrease -gt 0 ] && echo 'var(--success-green)' || echo 'var(--text-light)');">
                                $([ $cmd_decrease -gt 0 ] && echo "-$cmd_decrease" || echo "$(( AFTER_SMTP_CMDS_COUNT - BEFORE_SMTP_CMDS_COUNT ))")
                            </td>
                            <td>공격 벡터 감소</td>
                        </tr>
                        <tr>
                            <td><strong>DATA 명령 시도</strong></td>
                            <td>$BEFORE_DATA_ATTEMPTS</td>
                            <td>$AFTER_DATA_ATTEMPTS</td>
                            <td style="color: $([ $data_cmd_decrease -gt 0 ] && echo 'var(--success-green)' || echo 'var(--text-light)');">
                                $([ $data_cmd_decrease -gt 0 ] && echo "-$data_cmd_decrease" || echo "$(( AFTER_DATA_ATTEMPTS - BEFORE_DATA_ATTEMPTS ))")
                            </td>
                            <td>메일 전송 차단</td>
                        </tr>
                        <tr>
                            <td><strong>5xx 거부 응답</strong></td>
                            <td>$BEFORE_REJECT_COUNT</td>
                            <td>$AFTER_REJECT_COUNT</td>
                            <td style="color: $([ $reject_increase -gt 0 ] && echo 'var(--success-green)' || echo 'var(--text-light)');">
                                $([ $reject_increase -gt 0 ] && echo "+$reject_increase" || echo "$reject_increase")
                            </td>
                            <td>액세스 제어 강화</td>
                        </tr>
                        <tr>
                            <td><strong>인증 실패</strong></td>
                            <td>$BEFORE_AUTH_FAILURES</td>
                            <td>$AFTER_AUTH_FAILURES</td>
                            <td style="color: $([ $auth_failure_increase -gt 0 ] && echo 'var(--success-green)' || echo 'var(--text-light)');">
                                $([ $auth_failure_increase -gt 0 ] && echo "+$auth_failure_increase" || echo "$auth_failure_increase")
                            </td>
                            <td>인증 보안 강화</td>
                        </tr>
                        <tr style="background: var(--primary-light); font-weight: bold;">
                            <td><strong>종합 보안 점수</strong></td>
                            <td colspan="3" style="text-align: center;">$security_score / 100</td>
                            <td>$([ $security_score -ge 70 ] && echo '강력함' || [ $security_score -ge 40 ] && echo '양호' || [ $security_score -ge 20 ] && echo '보통' || echo '취약')</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Collapsible Sections -->
        <div class="collapsible">
            <div class="collapsible-header">
                Experiment Details & Files
            </div>
            <div class="collapsible-content">
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                    <div>
                        <h4>Environment</h4>
                        <div style="font-size: 0.875rem;">
                            $ENVIRONMENT_INFO_HTML
                        </div>
                    </div>
                    <div>
                        <h4>Files</h4>
                        <div style="font-size: 0.875rem;">
                            $EXPERIMENT_ARTIFACTS_HTML
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                Before/After Analysis Comparison (Diff)
            </div>
            <div class="collapsible-content">
                <p>다음은 강화 전후 분석 파일 간의 차이점입니다.</p>
                $DIFF_CONTENT_HTML
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                Analysis Criteria & Interpretation Guide
            </div>
            <div class="collapsible-content">
                <h4>보안 점수 기준</h4>
                <ul>
                    <li><strong>강력한 보안 강화 (70점+):</strong> 다층적 보안 개선 - 거부 응답 증가 + DATA 명령 차단 + 인증 강화</li>
                    <li><strong>보안 강화 성공 (40-69점):</strong> 핵심 보안 지표 개선 - 5xx 거부 응답 증가 또는 DATA 명령 차단</li>
                    <li><strong>부분적 개선 (20-39점):</strong> 일부 보안 요소 개선되나 추가 조치 필요</li>
                    <li><strong>강화 실패 (0-19점)::</strong> 거부 응답 증가 없이 공격 명령 여전히 실행 가능</li>
                </ul>
                
                <h4>트래픽 분석 기준</h4>
                <ul>
                    <li><strong>패킷 수 기준:</strong> SMTP 특성상 1-3개 차이는 정상 (TCP 핸드셰이크/세션 종료 차이)</li>
                    <li><strong>핵심 지표:</strong> SMTP 응답 코드 변화가 패킷 수보다 중요한 보안 지표</li>
                    <li><strong>동적 임계값:</strong> 패킷 수에 따라 유의미한 변화 기준을 조정</li>
                </ul>
                
                <p><small><strong>참고:</strong> 이 판단은 SMTP 패킷 캡처 및 응답 코드 분석에 기반합니다. 실제 보안 설정은 추가적인 검토가 필요할 수 있습니다.</small></p>
            </div>
        </div>

        <div class="footer">
            <p>🔬 SMTP/DNS Vulnerability Lab Report Generator | 
            자동화된 보안 분석 도구로 생성됨 | 
            <strong>핵심 보안 분석 리포트</strong></p>
        </div>
    </div>
</body>
</html>
EOF

echo "INFO: HTML 보고서 생성 완료: $REPORT_FILE"
echo "INFO: 공격 스크립트 실행 결과, CVSS 점수, 하드닝 효과가 포함된 통합 보고서"
# 운영체제에 따라 자동으로 브라우저에서 열기 (선택 사항)
xdg-open "$REPORT_FILE" 2>/dev/null || open "$REPORT_FILE" 2>/dev/null || echo "INFO: 브라우저에서 $REPORT_FILE 파일을 수동으로 열어주세요."

exit 0