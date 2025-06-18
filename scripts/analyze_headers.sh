#!/bin/bash
set -e

# SPF/DKIM/DMARC 헤더 분석 스크립트
# 목표: 메일 헤더에서 인증 관련 정보 추출 및 누락 여부 확인

ATTACK_ID="$1"
EMAIL_FILE="$2"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="HEADERS-${TIMESTAMP}"
fi

ARTIFACTS_DIR="/artifacts"
DNS_IP="172.28.0.253"

# 테스트할 도메인들
TEST_DOMAINS=(
    "localhost"
    "example.com"
    "mail.local"
    "test.com"
)

echo "INFO: Starting SPF/DKIM/DMARC analysis - ID: $ATTACK_ID"

# DNS 도구 확인
if command -v dig >/dev/null 2>&1; then
    DNS_TOOL="dig"
elif command -v nslookup >/dev/null 2>&1; then
    DNS_TOOL="nslookup"
elif command -v host >/dev/null 2>&1; then
    DNS_TOOL="host"
else
    echo "WARNING: No DNS query tools available - skipping DNS record checks"
    DNS_TOOL="none"
fi

echo "INFO: Using $DNS_TOOL for DNS queries"

# DNS 쿼리 함수
query_txt_record() {
    local domain="$1"
    local server="$2"
    
    if [[ "$DNS_TOOL" == "none" ]]; then
        echo "DNS_TOOL_NOT_AVAILABLE"
        return
    fi
    
    case "$DNS_TOOL" in
        "dig")
            timeout 10 dig @$server $domain TXT +short 2>/dev/null || echo "QUERY_FAILED"
            ;;
        "nslookup")
            timeout 10 nslookup -type=TXT $domain $server 2>/dev/null | grep "text =" | sed 's/.*text = //' | tr -d '"' || echo "QUERY_FAILED"
            ;;
        "host")
            timeout 10 host -t TXT $domain $server 2>/dev/null | grep "descriptive text" | sed 's/.*descriptive text "//' | sed 's/"$//' || echo "QUERY_FAILED"
            ;;
    esac
}

# 1. 메일 헤더 분석 (파일이 제공된 경우)
if [[ -n "$EMAIL_FILE" && -f "$EMAIL_FILE" ]]; then
    echo "INFO: Analyzing email headers from file: $EMAIL_FILE"
    HEADER_ANALYSIS_FILE="$ARTIFACTS_DIR/header_analysis_$ATTACK_ID.txt"
    
    {
        echo "===== Email Header Analysis ====="
        echo "Source file: $EMAIL_FILE"
        echo "Timestamp: $(date)"
        echo ""
        
        echo "=== Raw Headers ==="
        head -50 "$EMAIL_FILE" | grep -E "^[A-Za-z-]+:" || echo "No standard headers found"
        echo ""
        
        echo "=== Authentication Results ==="
        grep -i "Authentication-Results:" "$EMAIL_FILE" || echo "No Authentication-Results header"
        grep -i "Received-SPF:" "$EMAIL_FILE" || echo "No Received-SPF header"
        grep -i "DKIM-Signature:" "$EMAIL_FILE" || echo "No DKIM-Signature header"
        grep -i "DMARC.*pass\|DMARC.*fail" "$EMAIL_FILE" || echo "No DMARC results found"
        echo ""
        
        echo "=== Return-Path and From Analysis ==="
        grep -i "Return-Path:" "$EMAIL_FILE" || echo "No Return-Path header"
        grep -i "From:" "$EMAIL_FILE" || echo "No From header"
        grep -i "Reply-To:" "$EMAIL_FILE" || echo "No Reply-To header"
        echo ""
        
    } > $HEADER_ANALYSIS_FILE
    
    echo "INFO: Header analysis saved to: $HEADER_ANALYSIS_FILE"
else
    echo "INFO: No email file provided, skipping header analysis"
fi

# 2. DNS 레코드 확인 (SPF, DKIM, DMARC)
echo "INFO: Checking DNS records for authentication policies..."
DNS_RECORDS_FILE="$ARTIFACTS_DIR/dns_auth_records_$ATTACK_ID.txt"

{
    echo "===== DNS Authentication Records Check ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Testing domains for SPF, DKIM, and DMARC records..."
    echo ""
} > $DNS_RECORDS_FILE

SPF_MISSING_COUNT=0
DMARC_MISSING_COUNT=0
WEAK_SPF_COUNT=0
WEAK_DMARC_COUNT=0

if [[ "$DNS_TOOL" != "none" ]]; then
    for domain in "${TEST_DOMAINS[@]}"; do
        echo "=== Testing domain: $domain ===" >> $DNS_RECORDS_FILE
        
        # SPF 레코드 확인
        echo "Checking SPF record for $domain..." >> $DNS_RECORDS_FILE
        SPF_RESULT=$(query_txt_record "$domain" "$DNS_IP")
        
        if [[ "$SPF_RESULT" != "QUERY_FAILED" && "$SPF_RESULT" != "DNS_TOOL_NOT_AVAILABLE" ]]; then
            SPF_RECORD=$(echo "$SPF_RESULT" | grep -i "v=spf1" | head -1)
            if [[ -n "$SPF_RECORD" ]]; then
                echo "FOUND SPF: $SPF_RECORD" >> $DNS_RECORDS_FILE
                
                # SPF 정책 강도 확인
                if echo "$SPF_RECORD" | grep -q "~all"; then
                    echo "WEAK SPF: Uses ~all (soft fail)" >> $DNS_RECORDS_FILE
                    WEAK_SPF_COUNT=$((WEAK_SPF_COUNT + 1))
                elif echo "$SPF_RECORD" | grep -q "?all"; then
                    echo "WEAK SPF: Uses ?all (neutral)" >> $DNS_RECORDS_FILE
                    WEAK_SPF_COUNT=$((WEAK_SPF_COUNT + 1))
                elif echo "$SPF_RECORD" | grep -q "+all"; then
                    echo "VULNERABLE SPF: Uses +all (pass all)" >> $DNS_RECORDS_FILE
                    WEAK_SPF_COUNT=$((WEAK_SPF_COUNT + 1))
                elif echo "$SPF_RECORD" | grep -q "\-all"; then
                    echo "STRONG SPF: Uses -all (hard fail)" >> $DNS_RECORDS_FILE
                fi
            else
                echo "NO SPF: No SPF record found for $domain" >> $DNS_RECORDS_FILE
                SPF_MISSING_COUNT=$((SPF_MISSING_COUNT + 1))
            fi
        else
            echo "ERROR: SPF query failed for $domain" >> $DNS_RECORDS_FILE
            SPF_MISSING_COUNT=$((SPF_MISSING_COUNT + 1))
        fi
        
        # DMARC 레코드 확인
        echo "Checking DMARC record for $domain..." >> $DNS_RECORDS_FILE
        DMARC_DOMAIN="_dmarc.$domain"
        DMARC_RESULT=$(query_txt_record "$DMARC_DOMAIN" "$DNS_IP")
        
        if [[ "$DMARC_RESULT" != "QUERY_FAILED" && "$DMARC_RESULT" != "DNS_TOOL_NOT_AVAILABLE" ]]; then
            DMARC_RECORD=$(echo "$DMARC_RESULT" | grep -i "v=DMARC1" | head -1)
            if [[ -n "$DMARC_RECORD" ]]; then
                echo "FOUND DMARC: $DMARC_RECORD" >> $DNS_RECORDS_FILE
                
                # DMARC 정책 강도 확인
                if echo "$DMARC_RECORD" | grep -q "p=none"; then
                    echo "WEAK DMARC: Policy set to 'none'" >> $DNS_RECORDS_FILE
                    WEAK_DMARC_COUNT=$((WEAK_DMARC_COUNT + 1))
                elif echo "$DMARC_RECORD" | grep -q "p=quarantine"; then
                    echo "MODERATE DMARC: Policy set to 'quarantine'" >> $DNS_RECORDS_FILE
                elif echo "$DMARC_RECORD" | grep -q "p=reject"; then
                    echo "STRONG DMARC: Policy set to 'reject'" >> $DNS_RECORDS_FILE
                fi
            else
                echo "NO DMARC: No DMARC record found for $domain" >> $DNS_RECORDS_FILE
                DMARC_MISSING_COUNT=$((DMARC_MISSING_COUNT + 1))
            fi
        else
            echo "ERROR: DMARC query failed for $domain" >> $DNS_RECORDS_FILE
            DMARC_MISSING_COUNT=$((DMARC_MISSING_COUNT + 1))
        fi
        
        # DKIM 레코드 확인 (일반적인 셀렉터들 시도)
        echo "Checking DKIM records for $domain..." >> $DNS_RECORDS_FILE
        DKIM_SELECTORS=("default" "selector1" "selector2" "google" "mail" "smtp" "k1")
        DKIM_FOUND=false
        
        for selector in "${DKIM_SELECTORS[@]}"; do
            DKIM_DOMAIN="${selector}._domainkey.$domain"
            DKIM_RESULT=$(query_txt_record "$DKIM_DOMAIN" "$DNS_IP")
            
            if [[ "$DKIM_RESULT" != "QUERY_FAILED" && "$DKIM_RESULT" != "DNS_TOOL_NOT_AVAILABLE" ]]; then
                if echo "$DKIM_RESULT" | grep -q "v=DKIM1\|k="; then
                    echo "FOUND DKIM ($selector): $DKIM_RESULT" >> $DNS_RECORDS_FILE
                    DKIM_FOUND=true
                    break
                fi
            fi
        done
        
        if [ "$DKIM_FOUND" = false ]; then
            echo "NO DKIM: No DKIM records found for common selectors" >> $DNS_RECORDS_FILE
        fi
        
        echo "---" >> $DNS_RECORDS_FILE
    done
else
    echo "DNS tool not available - skipping DNS record checks" >> $DNS_RECORDS_FILE
    echo "All domains will be counted as missing SPF/DMARC records" >> $DNS_RECORDS_FILE
    SPF_MISSING_COUNT=${#TEST_DOMAINS[@]}
    DMARC_MISSING_COUNT=${#TEST_DOMAINS[@]}
fi

# 3. 실제 스푸핑 테스트 생성
echo "INFO: Generating spoofing test scenarios..."
SPOOFING_TEST_FILE="$ARTIFACTS_DIR/spoofing_test_$ATTACK_ID.txt"

{
    echo "===== Email Spoofing Test Scenarios ====="
    echo "Timestamp: $(date)"
    echo ""
    
    echo "=== Test 1: Return-Path Spoofing ==="
    echo "From: legitimate@${TEST_DOMAINS[0]}"
    echo "Return-Path: attacker@evil.com"
    echo "Subject: Return-Path Spoofing Test"
    echo "Body: This email has mismatched From and Return-Path headers"
    echo ""
    
    echo "=== Test 2: Display Name Spoofing ==="
    echo 'From: "Important Bank" <attacker@evil.com>'
    echo "Subject: Display Name Spoofing"
    echo "Body: The display name suggests a trusted sender but the actual address is different"
    echo ""
    
    echo "=== Test 3: Domain Spoofing ==="
    echo "From: admin@${TEST_DOMAINS[0]}"
    echo "Subject: Domain Spoofing Test"
    echo "Body: This email claims to be from ${TEST_DOMAINS[0]} but may not be authenticated"
    echo ""
    
    echo "=== Test 4: Reply-To Manipulation ==="
    echo "From: noreply@${TEST_DOMAINS[0]}"
    echo "Reply-To: attacker@evil.com"
    echo "Subject: Reply-To Manipulation"
    echo "Body: Replies will go to a different address than the sender"
    echo ""
    
} > $SPOOFING_TEST_FILE

# 4. 스푸핑 공격 실행 (실제 메일 전송 시도)
echo "INFO: Attempting email spoofing attacks..."
SPOOFING_RESULTS_FILE="$ARTIFACTS_DIR/spoofing_results_$ATTACK_ID.txt"

{
    echo "===== Email Spoofing Attack Results ====="
    echo "Timestamp: $(date)"
    echo ""
} > $SPOOFING_RESULTS_FILE

# swaks를 사용한 스푸핑 시도
SPOOFING_SUCCESS_COUNT=0
SPOOFING_ATTEMPT_COUNT=0

for domain in "${TEST_DOMAINS[@]}"; do
    SPOOFING_ATTEMPT_COUNT=$((SPOOFING_ATTEMPT_COUNT + 1))
    
    echo "=== Spoofing attempt $SPOOFING_ATTEMPT_COUNT: $domain ===" >> $SPOOFING_RESULTS_FILE
    
    # 기본 스푸핑 시도
    if timeout 30 swaks --to victim@localhost \
                        --from "admin@$domain" \
                        --header "Subject: SPF Test - Spoofed from $domain" \
                        --body "This is a spoofing test from $domain" \
                        --server mail-postfix \
                        --port 25 \
                        --quit-after DATA >> $SPOOFING_RESULTS_FILE 2>&1; then
        
        if tail -10 $SPOOFING_RESULTS_FILE | grep -q "250.*Ok\|250.*Message accepted"; then
            echo "SPOOFING SUCCESS: Mail accepted from spoofed $domain" >> $SPOOFING_RESULTS_FILE
            SPOOFING_SUCCESS_COUNT=$((SPOOFING_SUCCESS_COUNT + 1))
        else
            echo "SPOOFING BLOCKED: Mail rejected from spoofed $domain" >> $SPOOFING_RESULTS_FILE
        fi
    else
        echo "SPOOFING ERROR: Connection failed for $domain" >> $SPOOFING_RESULTS_FILE
    fi
    
    echo "---" >> $SPOOFING_RESULTS_FILE
done

# 5. 결과 분석 및 요약
echo "INFO: Analyzing authentication results..."
SUMMARY_FILE="$ARTIFACTS_DIR/spf_dkim_dmarc_summary_$ATTACK_ID.txt"

{
    echo "===== SPF/DKIM/DMARC Analysis Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "Timestamp: $(date)"
    echo ""
    
    echo "Test Results:"
    echo "- Domains tested: ${#TEST_DOMAINS[@]}"
    echo "- SPF records missing: $SPF_MISSING_COUNT"
    echo "- DMARC records missing: $DMARC_MISSING_COUNT"
    echo "- Weak SPF policies: $WEAK_SPF_COUNT"
    echo "- Weak DMARC policies: $WEAK_DMARC_COUNT"
    echo "- Spoofing attempts: $SPOOFING_ATTEMPT_COUNT"
    echo "- Successful spoofing: $SPOOFING_SUCCESS_COUNT"
    echo ""
    
    # 보안 평가
    VULNERABILITY_SCORE=0
    
    if [ $SPF_MISSING_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 3))
    fi
    
    if [ $DMARC_MISSING_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 3))
    fi
    
    if [ $WEAK_SPF_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 2))
    fi
    
    if [ $WEAK_DMARC_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 2))
    fi
    
    if [ $SPOOFING_SUCCESS_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 4))
    fi
    
    if [ $VULNERABILITY_SCORE -ge 8 ]; then
        echo "SECURITY ASSESSMENT: HIGHLY VULNERABLE"
    elif [ $VULNERABILITY_SCORE -ge 5 ]; then
        echo "SECURITY ASSESSMENT: VULNERABLE"
    elif [ $VULNERABILITY_SCORE -ge 3 ]; then
        echo "SECURITY ASSESSMENT: MODERATE RISK"
    else
        echo "SECURITY ASSESSMENT: SECURE"
    fi
    
    echo ""
    echo "Vulnerabilities Found:"
    
    if [ $SPF_MISSING_COUNT -gt 0 ]; then
        echo "1. MISSING SPF Records:"
        echo "   - $SPF_MISSING_COUNT domains lack SPF protection"
        echo "   - Email spoofing is possible"
        echo "   - No sender IP validation"
    fi
    
    if [ $DMARC_MISSING_COUNT -gt 0 ]; then
        echo "2. MISSING DMARC Policies:"
        echo "   - $DMARC_MISSING_COUNT domains lack DMARC protection"
        echo "   - No action defined for failed authentication"
        echo "   - No reporting mechanism for abuse"
    fi
    
    if [ $WEAK_SPF_COUNT -gt 0 ]; then
        echo "3. WEAK SPF Policies:"
        echo "   - $WEAK_SPF_COUNT domains use soft fail (~all) or neutral (?all)"
        echo "   - Spoofed emails may still be delivered"
    fi
    
    if [ $WEAK_DMARC_COUNT -gt 0 ]; then
        echo "4. WEAK DMARC Policies:"
        echo "   - $WEAK_DMARC_COUNT domains use 'none' policy"
        echo "   - Failed authentication has no consequences"
    fi
    
    if [ $SPOOFING_SUCCESS_COUNT -gt 0 ]; then
        echo "5. SUCCESSFUL SPOOFING:"
        echo "   - $SPOOFING_SUCCESS_COUNT spoofing attempts succeeded"
        echo "   - Mail server accepts forged sender addresses"
        echo "   - No authentication enforcement"
    fi
    
    echo ""
    echo "Attack Scenarios:"
    echo "1. Email Spoofing:"
    echo "   - Send emails with forged From addresses"
    echo "   - Impersonate trusted domains/users"
    echo "2. Phishing Attacks:"
    echo "   - Use spoofed emails for credential theft"
    echo "   - Bypass email filters with trusted domains"
    echo "3. Business Email Compromise (BEC):"
    echo "   - Impersonate executives or partners"
    echo "   - Request fraudulent wire transfers"
    
    echo ""
    echo "Recommendations:"
    echo "1. Implement SPF records:"
    echo "   - Define authorized mail servers"
    echo "   - Use -all for strict policy"
    echo "2. Deploy DMARC policies:"
    echo "   - Start with p=none for monitoring"
    echo "   - Progress to p=quarantine then p=reject"
    echo "3. Configure DKIM signing:"
    echo "   - Sign outgoing emails with DKIM"
    echo "   - Publish DKIM public keys in DNS"
    echo "4. Enable authentication checking:"
    echo "   - Configure mail server to verify SPF/DKIM/DMARC"
    echo "   - Reject or quarantine failed authentication"
    
    echo ""
    echo "Artifacts generated:"
    if [[ -n "$EMAIL_FILE" ]]; then
        echo "- Header analysis: header_analysis_$ATTACK_ID.txt"
    fi
    echo "- DNS records: dns_auth_records_$ATTACK_ID.txt"
    echo "- Spoofing tests: spoofing_test_$ATTACK_ID.txt"
    echo "- Spoofing results: spoofing_results_$ATTACK_ID.txt"
    echo "- Summary: spf_dkim_dmarc_summary_$ATTACK_ID.txt"
    
} > $SUMMARY_FILE

echo "INFO: SPF/DKIM/DMARC analysis completed. Summary:"
cat $SUMMARY_FILE

# 6. 상세 결과 표시
echo ""
echo "===== Detailed Results ====="
echo "Missing SPF: $SPF_MISSING_COUNT domains"
echo "Missing DMARC: $DMARC_MISSING_COUNT domains"
echo "Successful spoofing: $SPOOFING_SUCCESS_COUNT/$SPOOFING_ATTEMPT_COUNT attempts"

exit 0
