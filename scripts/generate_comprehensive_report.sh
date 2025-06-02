#!/bin/bash
set -e

# 종합 보안 분석 리포트 생성 스크립트
# 목표: 모든 보안 테스트 결과를 통합하여 종합 리포트 생성

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="COMPREHENSIVE-${TIMESTAMP}"
fi

ARTIFACTS_DIR="/artifacts"
REPORT_FILE="$ARTIFACTS_DIR/comprehensive_security_report_$ATTACK_ID.txt"

echo "INFO: Generating comprehensive security report - ID: $ATTACK_ID"

# 1. 헤더 및 기본 정보
{
    echo "======================================================"
    echo "        COMPREHENSIVE SECURITY ASSESSMENT REPORT"
    echo "======================================================"
    echo ""
    echo "Report ID: $ATTACK_ID"
    echo "Generated: $(date)"
    echo "Lab Environment: SMTP & DNS Vulnerability Lab"
    echo ""
    echo "Executive Summary:"
    echo "This report presents a comprehensive security assessment"
    echo "of the email infrastructure including SMTP, DNS, and"
    echo "authentication mechanisms."
    echo ""
    echo "======================================================"
    echo ""
} > $REPORT_FILE

# 2. 테스트 결과 수집 함수
collect_test_results() {
    local test_type=$1
    local pattern=$2
    local description=$3
    
    echo "=== $description ===" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    # 최신 결과 파일들 찾기
    BEFORE_FILES=$(find $ARTIFACTS_DIR -name "*${pattern}*${ATTACK_ID}*BEFORE*" -type f 2>/dev/null | sort -r | head -3)
    AFTER_FILES=$(find $ARTIFACTS_DIR -name "*${pattern}*${ATTACK_ID}*AFTER*" -type f 2>/dev/null | sort -r | head -3)
    GENERAL_FILES=$(find $ARTIFACTS_DIR -name "*${pattern}*${ATTACK_ID}*" -type f 2>/dev/null | grep -v "BEFORE\|AFTER" | sort -r | head -3)
    
    if [[ -n "$BEFORE_FILES" || -n "$AFTER_FILES" || -n "$GENERAL_FILES" ]]; then
        echo "Test Status: EXECUTED" >> $REPORT_FILE
        echo "" >> $REPORT_FILE
        
        # Before 결과
        if [[ -n "$BEFORE_FILES" ]]; then
            echo "--- Before Hardening ---" >> $REPORT_FILE
            for file in $BEFORE_FILES; do
                if [[ -f "$file" ]]; then
                    echo "Source: $(basename $file)" >> $REPORT_FILE
                    # 요약 정보만 추출
                    grep -A 20 -B 5 "SECURITY ASSESSMENT\|VULNERABLE\|SECURE\|Summary" "$file" 2>/dev/null | head -25 >> $REPORT_FILE || echo "No assessment found" >> $REPORT_FILE
                    echo "" >> $REPORT_FILE
                    break
                fi
            done
        fi
        
        # After 결과
        if [[ -n "$AFTER_FILES" ]]; then
            echo "--- After Hardening ---" >> $REPORT_FILE
            for file in $AFTER_FILES; do
                if [[ -f "$file" ]]; then
                    echo "Source: $(basename $file)" >> $REPORT_FILE
                    grep -A 20 -B 5 "SECURITY ASSESSMENT\|VULNERABLE\|SECURE\|Summary" "$file" 2>/dev/null | head -25 >> $REPORT_FILE || echo "No assessment found" >> $REPORT_FILE
                    echo "" >> $REPORT_FILE
                    break
                fi
            done
        fi
        
        # General 결과 (before/after 구분 없음)
        if [[ -n "$GENERAL_FILES" ]]; then
            echo "--- Test Results ---" >> $REPORT_FILE
            for file in $GENERAL_FILES; do
                if [[ -f "$file" ]]; then
                    echo "Source: $(basename $file)" >> $REPORT_FILE
                    grep -A 20 -B 5 "SECURITY ASSESSMENT\|VULNERABLE\|SECURE\|Summary" "$file" 2>/dev/null | head -25 >> $REPORT_FILE || echo "No assessment found" >> $REPORT_FILE
                    echo "" >> $REPORT_FILE
                    break
                fi
            done
        fi
    else
        echo "Test Status: NOT EXECUTED" >> $REPORT_FILE
        echo "No test results found for this category." >> $REPORT_FILE
        echo "" >> $REPORT_FILE
    fi
    
    echo "----------------------------------------------------" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
}

# 3. 각 테스트 카테고리별 결과 수집
echo "INFO: Collecting STARTTLS test results..."
collect_test_results "starttls" "starttls" "STARTTLS Downgrade Attack Results"

echo "INFO: Collecting Open Relay test results..."
collect_test_results "openrelay" "openrelay\|relay" "Open Relay Attack Results"

echo "INFO: Collecting DNS test results..."
collect_test_results "dns" "dns_recursion\|dane" "DNS Security Test Results"

echo "INFO: Collecting Authentication test results..."
collect_test_results "auth" "auth_plain\|plaintext" "Authentication Security Test Results"

echo "INFO: Collecting SPF/DKIM/DMARC test results..."
collect_test_results "spfdkim" "spf_dkim_dmarc\|headers" "Email Authentication Test Results"

# 4. 전체 위험도 평가
echo "INFO: Performing risk assessment..."
{
    echo "======================================================"
    echo "                    RISK ASSESSMENT"
    echo "======================================================"
    echo ""
    
    # 각 카테고리별 위험도 점수 계산
    TOTAL_RISK_SCORE=0
    CRITICAL_ISSUES=0
    HIGH_ISSUES=0
    MEDIUM_ISSUES=0
    LOW_ISSUES=0
    
    # STARTTLS 위험도
    if find $ARTIFACTS_DIR -name "*starttls*$ATTACK_ID*" -type f -exec grep -l "VULNERABLE\|HIGHLY VULNERABLE" {} \; 2>/dev/null | grep -q .; then
        TOTAL_RISK_SCORE=$((TOTAL_RISK_SCORE + 3))
        HIGH_ISSUES=$((HIGH_ISSUES + 1))
        echo "❌ STARTTLS: HIGH RISK - Downgrade attacks possible" >> $REPORT_FILE
    elif find $ARTIFACTS_DIR -name "*starttls*$ATTACK_ID*" -type f -exec grep -l "SECURE" {} \; 2>/dev/null | grep -q .; then
        echo "✅ STARTTLS: SECURE - Proper TLS enforcement" >> $REPORT_FILE
    else
        echo "⚠️  STARTTLS: UNKNOWN - Test not completed" >> $REPORT_FILE
    fi
    
    # Open Relay 위험도
    if find $ARTIFACTS_DIR -name "*relay*$ATTACK_ID*" -type f -exec grep -l "VULNERABLE\|accepts.*relay" {} \; 2>/dev/null | grep -q .; then
        TOTAL_RISK_SCORE=$((TOTAL_RISK_SCORE + 4))
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        echo "❌ OPEN RELAY: CRITICAL - Unauthorized relay possible" >> $REPORT_FILE
    elif find $ARTIFACTS_DIR -name "*relay*$ATTACK_ID*" -type f -exec grep -l "SECURE\|rejected" {} \; 2>/dev/null | grep -q .; then
        echo "✅ OPEN RELAY: SECURE - Relay properly restricted" >> $REPORT_FILE
    else
        echo "⚠️  OPEN RELAY: UNKNOWN - Test not completed" >> $REPORT_FILE
    fi
    
    # DNS 위험도
    if find $ARTIFACTS_DIR -name "*dns*$ATTACK_ID*" -type f -exec grep -l "VULNERABLE\|recursion.*allowed" {} \; 2>/dev/null | grep -q .; then
        TOTAL_RISK_SCORE=$((TOTAL_RISK_SCORE + 2))
        MEDIUM_ISSUES=$((MEDIUM_ISSUES + 1))
        echo "❌ DNS: MEDIUM RISK - Recursion vulnerabilities detected" >> $REPORT_FILE
    elif find $ARTIFACTS_DIR -name "*dns*$ATTACK_ID*" -type f -exec grep -l "SECURE" {} \; 2>/dev/null | grep -q .; then
        echo "✅ DNS: SECURE - Proper recursion controls" >> $REPORT_FILE
    else
        echo "⚠️  DNS: UNKNOWN - Test not completed" >> $REPORT_FILE
    fi
    
    # Authentication 위험도
    if find $ARTIFACTS_DIR -name "*auth*$ATTACK_ID*" -type f -exec grep -l "VULNERABLE\|accepted.*without" {} \; 2>/dev/null | grep -q .; then
        TOTAL_RISK_SCORE=$((TOTAL_RISK_SCORE + 3))
        HIGH_ISSUES=$((HIGH_ISSUES + 1))
        echo "❌ AUTH: HIGH RISK - Plaintext authentication allowed" >> $REPORT_FILE
    elif find $ARTIFACTS_DIR -name "*auth*$ATTACK_ID*" -type f -exec grep -l "SECURE\|requires.*TLS" {} \; 2>/dev/null | grep -q .; then
        echo "✅ AUTH: SECURE - TLS required for authentication" >> $REPORT_FILE
    else
        echo "⚠️  AUTH: UNKNOWN - Test not completed" >> $REPORT_FILE
    fi
    
    # SPF/DKIM/DMARC 위험도
    if find $ARTIFACTS_DIR -name "*spf*$ATTACK_ID*" -name "*dmarc*$ATTACK_ID*" -type f -exec grep -l "VULNERABLE\|missing" {} \; 2>/dev/null | grep -q .; then
        TOTAL_RISK_SCORE=$((TOTAL_RISK_SCORE + 2))
        MEDIUM_ISSUES=$((MEDIUM_ISSUES + 1))
        echo "❌ EMAIL AUTH: MEDIUM RISK - Missing SPF/DKIM/DMARC" >> $REPORT_FILE
    elif find $ARTIFACTS_DIR -name "*spf*$ATTACK_ID*" -name "*dmarc*$ATTACK_ID*" -type f -exec grep -l "SECURE" {} \; 2>/dev/null | grep -q .; then
        echo "✅ EMAIL AUTH: SECURE - Proper authentication policies" >> $REPORT_FILE
    else
        echo "⚠️  EMAIL AUTH: UNKNOWN - Test not completed" >> $REPORT_FILE
    fi
    
    echo "" >> $REPORT_FILE
    echo "Overall Risk Assessment:" >> $REPORT_FILE
    echo "- Critical Issues: $CRITICAL_ISSUES" >> $REPORT_FILE
    echo "- High Risk Issues: $HIGH_ISSUES" >> $REPORT_FILE
    echo "- Medium Risk Issues: $MEDIUM_ISSUES" >> $REPORT_FILE
    echo "- Low Risk Issues: $LOW_ISSUES" >> $REPORT_FILE
    echo "- Total Risk Score: $TOTAL_RISK_SCORE/16" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    if [ $TOTAL_RISK_SCORE -ge 10 ]; then
        echo "🔴 OVERALL ASSESSMENT: CRITICAL RISK" >> $REPORT_FILE
        echo "   Immediate action required to secure infrastructure" >> $REPORT_FILE
    elif [ $TOTAL_RISK_SCORE -ge 6 ]; then
        echo "🟡 OVERALL ASSESSMENT: HIGH RISK" >> $REPORT_FILE
        echo "   Significant vulnerabilities present, prompt action needed" >> $REPORT_FILE
    elif [ $TOTAL_RISK_SCORE -ge 3 ]; then
        echo "🟠 OVERALL ASSESSMENT: MEDIUM RISK" >> $REPORT_FILE
        echo "   Some vulnerabilities present, review and improve security" >> $REPORT_FILE
    else
        echo "🟢 OVERALL ASSESSMENT: LOW RISK" >> $REPORT_FILE
        echo "   Good security posture, continue monitoring" >> $REPORT_FILE
    fi
    
    echo "" >> $REPORT_FILE
    echo "======================================================"
    echo "" >> $REPORT_FILE
    
} >> $REPORT_FILE

# 5. 권장사항
{
    echo "======================================================"
    echo "                   RECOMMENDATIONS"
    echo "======================================================"
    echo ""
    echo "Priority Actions:"
    echo ""
    
    if [ $CRITICAL_ISSUES -gt 0 ]; then
        echo "🔥 CRITICAL (Fix Immediately):"
        echo "   1. Disable open relay functionality"
        echo "   2. Configure proper relay restrictions"
        echo "   3. Implement sender authentication"
        echo ""
    fi
    
    if [ $HIGH_ISSUES -gt 0 ]; then
        echo "⚡ HIGH PRIORITY (Fix Within 24 Hours):"
        echo "   1. Enable STARTTLS enforcement"
        echo "   2. Require TLS for authentication"
        echo "   3. Disable plaintext authentication"
        echo ""
    fi
    
    if [ $MEDIUM_ISSUES -gt 0 ]; then
        echo "⚠️  MEDIUM PRIORITY (Fix Within 1 Week):"
        echo "   1. Configure SPF records"
        echo "   2. Implement DKIM signing"
        echo "   3. Deploy DMARC policies"
        echo "   4. Restrict DNS recursion"
        echo ""
    fi
    
    echo "General Security Improvements:"
    echo "1. Regular security assessments"
    echo "2. Monitor email traffic patterns"
    echo "3. Keep software updated"
    echo "4. Implement logging and alerting"
    echo "5. Review and update security policies"
    echo ""
    echo "======================================================"
    echo ""
    
    echo "Report generated by: SMTP & DNS Vulnerability Lab"
    echo "Tool version: 1.0"
    echo "For questions contact: security-team@organization.com"
    echo ""
    
} >> $REPORT_FILE

# CVSS 및 응답 분석 함수 추가
generate_cvss_analysis() {
    echo "=== CVSS 3.1 Risk Assessment ===" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    if [[ -x "/scripts/calc_cvss.py" ]]; then
        echo "Calculating CVSS scores for identified vulnerabilities..." >> $REPORT_FILE
        echo "" >> $REPORT_FILE
        
        # CVSS 점수 계산 및 테이블 형식으로 저장
        python3 /scripts/calc_cvss.py --format table >> $REPORT_FILE 2>/dev/null || {
            echo "CVSS calculation failed - manual review required" >> $REPORT_FILE
        }
        
        # JSON 파일도 생성
        python3 /scripts/calc_cvss.py --output "$ARTIFACTS_DIR/cvss_analysis_$ATTACK_ID.json" 2>/dev/null || true
        
        echo "" >> $REPORT_FILE
        echo "Detailed CVSS vectors saved to: cvss_analysis_$ATTACK_ID.json" >> $REPORT_FILE
    else
        echo "CVSS calculator not available" >> $REPORT_FILE
    fi
    echo "" >> $REPORT_FILE
}

analyze_smtp_responses() {
    echo "=== SMTP Response Code Analysis ===" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    # 가장 최근 PCAP 파일들에서 SMTP 응답 분석
    local pcap_files=$(find $ARTIFACTS_DIR -name "*.pcap" -type f 2>/dev/null | sort -r | head -2)
    
    if [[ -n "$pcap_files" && -x "/scripts/analyze_smtp_responses.sh" ]]; then
        for pcap_file in $pcap_files; do
            local basename=$(basename "$pcap_file" .pcap)
            echo "Analyzing SMTP responses from: $basename" >> $REPORT_FILE
            echo "----------------------------------------" >> $REPORT_FILE
            
            # SMTP 응답 분석 실행
            if /scripts/analyze_smtp_responses.sh "$pcap_file" >> $REPORT_FILE 2>/dev/null; then
                echo "" >> $REPORT_FILE
            else
                echo "Analysis failed for $basename" >> $REPORT_FILE
                echo "" >> $REPORT_FILE
            fi
        done
    else
        echo "No PCAP files found or analyzer not available" >> $REPORT_FILE
        echo "" >> $REPORT_FILE
    fi
}

generate_security_recommendations() {
    echo "=== Security Recommendations ===" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
    
    # CVSS 분석 결과 기반 권장사항
    local cvss_file="$ARTIFACTS_DIR/cvss_analysis_$ATTACK_ID.json"
    if [[ -f "$cvss_file" ]]; then
        echo "Based on CVSS analysis:" >> $REPORT_FILE
        
        # High/Critical 취약점에 대한 우선순위 권장사항
        local high_critical=$(jq -r '.cvss_analysis[] | select(.severity == "High" or .severity == "Critical") | "- \(.vulnerability_type): \(.description) (Score: \(.base_score))"' "$cvss_file" 2>/dev/null || echo "")
        
        if [[ -n "$high_critical" ]]; then
            echo "IMMEDIATE ACTION REQUIRED (High/Critical):" >> $REPORT_FILE
            echo "$high_critical" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
        fi
        
        # Medium 취약점
        local medium=$(jq -r '.cvss_analysis[] | select(.severity == "Medium") | "- \(.vulnerability_type): \(.description) (Score: \(.base_score))"' "$cvss_file" 2>/dev/null || echo "")
        
        if [[ -n "$medium" ]]; then
            echo "MEDIUM PRIORITY:" >> $REPORT_FILE
            echo "$medium" >> $REPORT_FILE
            echo "" >> $REPORT_FILE
        fi
    fi
    
    # 일반적인 보안 권장사항
    echo "General Security Hardening:" >> $REPORT_FILE
    echo "- Enable STARTTLS/TLS encryption for all SMTP communications" >> $REPORT_FILE
    echo "- Implement strict relay restrictions (prevent open relay)" >> $REPORT_FILE
    echo "- Configure proper authentication mechanisms" >> $REPORT_FILE
    echo "- Set up SPF, DKIM, and DMARC records" >> $REPORT_FILE
    echo "- Enable comprehensive logging and monitoring" >> $REPORT_FILE
    echo "- Regular security updates and patch management" >> $REPORT_FILE
    echo "- Implement rate limiting and anti-spam measures" >> $REPORT_FILE
    echo "" >> $REPORT_FILE
}

# 추가 분석 수행
generate_cvss_analysis
analyze_smtp_responses
generate_security_recommendations

echo "INFO: Comprehensive security report generated: $REPORT_FILE"
echo ""
echo "===== REPORT SUMMARY ====="
cat $REPORT_FILE | grep -A 10 "OVERALL ASSESSMENT"

exit 0
