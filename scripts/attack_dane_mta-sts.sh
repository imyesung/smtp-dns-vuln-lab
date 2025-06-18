#!/bin/bash
set -e

# DANE/MTA-STS 누락 공격 스크립트
# 목표: 메일 도메인의 DANE(TLSA) 및 MTA-STS 보안 정책 누락 여부 확인

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="DANE-STS-${TIMESTAMP}"
fi

DNS_TARGET="dns-dnsmasq"
DNS_IP="172.28.0.253"
ARTIFACTS_DIR="/artifacts"
TIMEOUT=10

# 테스트할 도메인들
TEST_DOMAINS=(
    "localhost"
    "example.com"
    "mail.local"
    "test.com"
    "target.local"
)

echo "INFO: Starting DANE/MTA-STS attack - ID: $ATTACK_ID"
echo "INFO: Testing domains for missing DANE TLSA and MTA-STS policies"

# DNS 도구 확인
if command -v dig >/dev/null 2>&1; then
    DNS_TOOL="dig"
elif command -v nslookup >/dev/null 2>&1; then
    DNS_TOOL="nslookup"
elif command -v host >/dev/null 2>&1; then
    DNS_TOOL="host"
else
    echo "ERROR: No DNS query tools available"
    exit 1
fi

echo "INFO: Using $DNS_TOOL for DNS queries"

# DNS 쿼리 함수
query_dns_record() {
    local domain="$1"
    local record_type="${2:-TXT}"
    local server="$3"
    
    case "$DNS_TOOL" in
        "dig")
            timeout $TIMEOUT dig @$server $domain $record_type +short 2>/dev/null || echo "QUERY_FAILED"
            ;;
        "nslookup")
            timeout $TIMEOUT nslookup -type=$record_type $domain $server 2>/dev/null | grep -E "text =|Address" | sed 's/.*text = //' || echo "QUERY_FAILED"
            ;;
        "host")
            timeout $TIMEOUT host -t $record_type $domain $server 2>/dev/null | grep -E "descriptive text|address" || echo "QUERY_FAILED"
            ;;
    esac
}

# 1. DANE TLSA 레코드 확인
echo "INFO: Testing for DANE TLSA records..."
DANE_FILE="$ARTIFACTS_DIR/dane_test_$ATTACK_ID.txt"
{
    echo "===== DANE TLSA Record Test ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Checking for TLSA records on mail domains..."
    echo ""
} > $DANE_FILE

DANE_MISSING_COUNT=0
DANE_TOTAL_COUNT=0

for domain in "${TEST_DOMAINS[@]}"; do
    DANE_TOTAL_COUNT=$((DANE_TOTAL_COUNT + 1))
    
    # SMTP 포트(25)용 TLSA 레코드 확인
    TLSA_QUERY="_25._tcp.$domain"
    echo "Testing TLSA for: $TLSA_QUERY" >> $DANE_FILE
    
    TLSA_RESULT=$(query_dns_record "$TLSA_QUERY" "TLSA" "$DNS_IP")
    if [[ "$TLSA_RESULT" != "QUERY_FAILED" && -n "$TLSA_RESULT" ]]; then
        echo "FOUND TLSA: $TLSA_RESULT" >> $DANE_FILE
    else
        echo "NO TLSA: No TLSA record found for $domain" >> $DANE_FILE
        DANE_MISSING_COUNT=$((DANE_MISSING_COUNT + 1))
    fi
    
    # SUBMISSION 포트(587)용 TLSA 레코드도 확인
    TLSA_QUERY_587="_587._tcp.$domain"
    echo "Testing TLSA for: $TLSA_QUERY_587" >> $DANE_FILE
    
    TLSA_RESULT_587=$(query_dns_record "$TLSA_QUERY_587" "TLSA" "$DNS_IP")
    if [[ "$TLSA_RESULT_587" != "QUERY_FAILED" && -n "$TLSA_RESULT_587" ]]; then
        echo "FOUND TLSA (587): $TLSA_RESULT_587" >> $DANE_FILE
    else
        echo "NO TLSA (587): No TLSA record found for port 587" >> $DANE_FILE
    fi
    
    echo "---" >> $DANE_FILE
done

# 2. MTA-STS 정책 확인
echo "INFO: Testing for MTA-STS policies..."
MTA_STS_FILE="$ARTIFACTS_DIR/mta_sts_test_$ATTACK_ID.txt"
{
    echo "===== MTA-STS Policy Test ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Checking for MTA-STS policies..."
    echo ""
} > $MTA_STS_FILE

MTA_STS_MISSING_COUNT=0
MTA_STS_TOTAL_COUNT=0

for domain in "${TEST_DOMAINS[@]}"; do
    MTA_STS_TOTAL_COUNT=$((MTA_STS_TOTAL_COUNT + 1))
    
    # MTA-STS TXT 레코드 확인
    STS_QUERY="_mta-sts.$domain"
    echo "Testing MTA-STS TXT for: $STS_QUERY" >> $MTA_STS_FILE
    
    STS_RESULT=$(query_dns_record "$STS_QUERY" "TXT" "$DNS_IP")
    if [[ "$STS_RESULT" != "QUERY_FAILED" && -n "$STS_RESULT" ]] && echo "$STS_RESULT" | grep -qi "v=STSv1"; then
        echo "FOUND MTA-STS: $STS_RESULT" >> $MTA_STS_FILE
        
        # MTA-STS 정책 내용 확인 시도 (HTTP/HTTPS)
        echo "Attempting to fetch MTA-STS policy for $domain..." >> $MTA_STS_FILE
        if command -v curl >/dev/null 2>&1; then
            if timeout $TIMEOUT curl -s "https://mta-sts.$domain/.well-known/mta-sts.txt" >> $MTA_STS_FILE 2>&1; then
                echo "MTA-STS policy fetched successfully" >> $MTA_STS_FILE
            else
                echo "FAILED: Cannot fetch MTA-STS policy file" >> $MTA_STS_FILE
            fi
        else
            echo "curl not available - cannot fetch policy file" >> $MTA_STS_FILE
        fi
    else
        echo "NO MTA-STS: No MTA-STS record found for $domain" >> $MTA_STS_FILE
        MTA_STS_MISSING_COUNT=$((MTA_STS_MISSING_COUNT + 1))
    fi
    echo "---" >> $MTA_STS_FILE
done

# 3. SMTP TLS Reporting 확인
echo "INFO: Testing for SMTP TLS Reporting..."
TLS_RPT_FILE="$ARTIFACTS_DIR/tls_rpt_test_$ATTACK_ID.txt"
{
    echo "===== SMTP TLS Reporting Test ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Checking for TLS reporting policies..."
    echo ""
} > $TLS_RPT_FILE

TLS_RPT_MISSING_COUNT=0

for domain in "${TEST_DOMAINS[@]}"; do
    # TLS-RPT TXT 레코드 확인
    RPT_QUERY="_smtp._tls.$domain"
    echo "Testing TLS-RPT for: $RPT_QUERY" >> $TLS_RPT_FILE
    
    RPT_RESULT=$(query_dns_record "$RPT_QUERY" "TXT" "$DNS_IP")
    if [[ "$RPT_RESULT" != "QUERY_FAILED" && -n "$RPT_RESULT" ]] && echo "$RPT_RESULT" | grep -qi "v=TLSRPTv1"; then
        echo "FOUND TLS-RPT: $RPT_RESULT" >> $TLS_RPT_FILE
    else
        echo "NO TLS-RPT: No TLS reporting record found for $domain" >> $TLS_RPT_FILE
        TLS_RPT_MISSING_COUNT=$((TLS_RPT_MISSING_COUNT + 1))
    fi
    echo "---" >> $TLS_RPT_FILE
done

# 4. 메일 서버 TLS 설정 확인
echo "INFO: Testing mail server TLS configuration..."
TLS_TEST_FILE="$ARTIFACTS_DIR/smtp_tls_test_$ATTACK_ID.txt"
{
    echo "===== SMTP TLS Configuration Test ====="
    echo "Timestamp: $(date)"
    echo "Testing mail server TLS support..."
    echo ""
} > $TLS_TEST_FILE

# mail-postfix 서버의 TLS 지원 확인
SMTP_TLS_SUPPORTED=false
{
    echo "EHLO test.com"
    sleep 2
    echo "STARTTLS"
    sleep 1
    echo "QUIT"
} | timeout $TIMEOUT nc mail-postfix 25 >> $TLS_TEST_FILE 2>&1

if grep -q "220.*ready for tls\|STARTTLS" $TLS_TEST_FILE; then
    SMTP_TLS_SUPPORTED=true
    echo "TLS SUPPORTED: SMTP server supports STARTTLS" >> $TLS_TEST_FILE
else
    echo "TLS NOT SUPPORTED: No STARTTLS support detected" >> $TLS_TEST_FILE
fi

# 5. 결과 분석 및 요약
echo "INFO: Analyzing DANE/MTA-STS results..."
SUMMARY_FILE="$ARTIFACTS_DIR/dane_mta_sts_summary_$ATTACK_ID.txt"
{
    echo "===== DANE/MTA-STS Attack Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "DNS Tool Used: $DNS_TOOL"
    echo "Timestamp: $(date)"
    echo ""
    
    echo "Test Results:"
    echo "- Domains tested: ${#TEST_DOMAINS[@]}"
    echo "- DANE TLSA missing: $DANE_MISSING_COUNT/$DANE_TOTAL_COUNT"
    echo "- MTA-STS missing: $MTA_STS_MISSING_COUNT/$MTA_STS_TOTAL_COUNT"
    echo "- TLS-RPT missing: $TLS_RPT_MISSING_COUNT/${#TEST_DOMAINS[@]}"
    echo "- SMTP TLS supported: $SMTP_TLS_SUPPORTED"
    echo ""
    
    # 보안 평가
    VULNERABILITY_SCORE=0
    
    if [ $DANE_MISSING_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 3))
    fi
    
    if [ $MTA_STS_MISSING_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 3))
    fi
    
    if [ $TLS_RPT_MISSING_COUNT -gt 0 ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 1))
    fi
    
    if [ "$SMTP_TLS_SUPPORTED" = false ]; then
        VULNERABILITY_SCORE=$((VULNERABILITY_SCORE + 4))
    fi
    
    if [ $VULNERABILITY_SCORE -ge 7 ]; then
        echo "SECURITY ASSESSMENT: HIGHLY VULNERABLE"
    elif [ $VULNERABILITY_SCORE -ge 4 ]; then
        echo "SECURITY ASSESSMENT: VULNERABLE"
    elif [ $VULNERABILITY_SCORE -ge 2 ]; then
        echo "SECURITY ASSESSMENT: MODERATE RISK"
    else
        echo "SECURITY ASSESSMENT: SECURE"
    fi
    
    echo ""
    echo "Note: DNS queries performed with $DNS_TOOL due to tool availability"
    
    echo "Vulnerabilities Found:"
    
    if [ $DANE_MISSING_COUNT -gt 0 ]; then
        echo "1. MISSING DANE TLSA Records:"
        echo "   - Mail domains lack TLSA records"
        echo "   - Vulnerable to man-in-the-middle attacks"
        echo "   - No certificate pinning protection"
    fi
    
    if [ $MTA_STS_MISSING_COUNT -gt 0 ]; then
        echo "2. MISSING MTA-STS Policies:"
        echo "   - No mail transport security policies"
        echo "   - Vulnerable to TLS downgrade attacks"
        echo "   - No mandatory TLS enforcement"
    fi
    
    if [ $TLS_RPT_MISSING_COUNT -gt 0 ]; then
        echo "3. MISSING TLS Reporting:"
        echo "   - No TLS failure reporting configured"
        echo "   - Cannot detect TLS attacks or failures"
    fi
    
    if [ "$SMTP_TLS_SUPPORTED" = false ]; then
        echo "4. NO TLS SUPPORT:"
        echo "   - SMTP server does not support STARTTLS"
        echo "   - All mail transmitted in plaintext"
        echo "   - Highly vulnerable to eavesdropping"
    fi
    
    echo ""
    echo "Attack Scenarios:"
    echo "1. Man-in-the-Middle (MITM):"
    echo "   - Intercept mail connections without DANE"
    echo "   - Present fraudulent certificates"
    echo "2. TLS Downgrade:"
    echo "   - Force plaintext communication"
    echo "   - Bypass encryption without MTA-STS"
    echo "3. Traffic Interception:"
    echo "   - Monitor all mail content and credentials"
    echo "   - No detection without TLS reporting"
    
    echo ""
    echo "Recommendations:"
    echo "1. Implement DANE TLSA records:"
    echo "   - Create TLSA records for mail servers"
    echo "   - Pin certificates in DNS"
    echo "2. Deploy MTA-STS policies:"
    echo "   - Require TLS for all mail connections"
    echo "   - Publish policy at https://mta-sts.domain/.well-known/mta-sts.txt"
    echo "3. Configure TLS reporting:"
    echo "   - Set up _smtp._tls.domain TXT records"
    echo "   - Monitor TLS failures and attacks"
    echo "4. Enable SMTP TLS:"
    echo "   - Configure STARTTLS on mail servers"
    echo "   - Require encryption for authentication"
    
    echo ""
    echo "Artifacts generated:"
    echo "- DANE test: dane_test_$ATTACK_ID.txt"
    echo "- MTA-STS test: mta_sts_test_$ATTACK_ID.txt"
    echo "- TLS-RPT test: tls_rpt_test_$ATTACK_ID.txt"
    echo "- SMTP TLS test: smtp_tls_test_$ATTACK_ID.txt"
    echo "- Summary: dane_mta_sts_summary_$ATTACK_ID.txt"
    
} > $SUMMARY_FILE

echo "INFO: DANE/MTA-STS attack completed. Summary:"
cat $SUMMARY_FILE

exit 0
