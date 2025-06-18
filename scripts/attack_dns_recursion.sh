#!/bin/bash
set -e

# DNS 재귀 질의 공격 스크립트
# 목표: DNS 서버가 재귀 질의를 허용하는지 확인하고 증폭 공격 가능성 테스트

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="DNS-REC-${TIMESTAMP}"
fi

DNS_TARGET="dns-dnsmasq"
DNS_IP="172.28.0.253"
DNS_PORT=53
ARTIFACTS_DIR="/artifacts"
TIMEOUT=10

# 외부 테스트용 도메인들
TEST_DOMAINS=(
    "google.com"
    "cloudflare.com"
    "microsoft.com"
    "github.com"
    "stackoverflow.com"
)

echo "INFO: Starting DNS recursion attack - ID: $ATTACK_ID"
echo "INFO: Target DNS: $DNS_TARGET ($DNS_IP:$DNS_PORT)"

# DNS 도구 확인 및 설정
if command -v dig >/dev/null 2>&1; then
    DNS_TOOL="dig"
    echo "INFO: Using dig for DNS queries"
elif command -v nslookup >/dev/null 2>&1; then
    DNS_TOOL="nslookup"
    echo "INFO: Using nslookup for DNS queries"
elif command -v host >/dev/null 2>&1; then
    DNS_TOOL="host"
    echo "INFO: Using host for DNS queries"
else
    echo "ERROR: No DNS query tools available (dig, nslookup, host)"
    exit 1
fi

# DNS 쿼리 함수
query_dns() {
    local domain="$1"
    local record_type="${2:-A}"
    local server="$3"
    
    case "$DNS_TOOL" in
        "dig")
            timeout $TIMEOUT dig @$server $domain $record_type +short 2>/dev/null || echo "QUERY_FAILED"
            ;;
        "nslookup")
            timeout $TIMEOUT nslookup -type=$record_type $domain $server 2>/dev/null | grep -E "^(Name|Address|Answer)" || echo "QUERY_FAILED"
            ;;
        "host")
            timeout $TIMEOUT host -t $record_type $domain $server 2>/dev/null || echo "QUERY_FAILED"
            ;;
    esac
}

# 1. DNS 서버 연결 확인
echo "INFO: Testing DNS server connectivity..."
if nc -uz $DNS_IP $DNS_PORT -w $TIMEOUT; then
    echo "SUCCESS: DNS server is reachable on $DNS_IP:$DNS_PORT"
else
    echo "ERROR: Cannot reach DNS server $DNS_IP:$DNS_PORT"
    exit 1
fi

# 2. 기본 DNS 질의 테스트
echo "INFO: Testing basic DNS queries..."
{
    echo "===== Basic DNS Query Test ====="
    echo "Timestamp: $(date)"
    echo "Target: $DNS_IP:$DNS_PORT"
    echo "DNS Tool: $DNS_TOOL"
    echo ""
} > $ARTIFACTS_DIR/dns_basic_$ATTACK_ID.txt

# 로컬 도메인 질의 (정상 동작 확인)
echo "INFO: Querying local domain..."
LOCAL_RESULT=$(query_dns "localhost" "A" "$DNS_IP")
echo "Local query result: $LOCAL_RESULT" >> $ARTIFACTS_DIR/dns_basic_$ATTACK_ID.txt

# 3. 재귀 질의 테스트 (외부 도메인)
echo "INFO: Testing recursive queries for external domains..."
RECURSION_FILE="$ARTIFACTS_DIR/dns_recursion_$ATTACK_ID.txt"
{
    echo "===== DNS Recursion Test ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Testing external domain resolution..."
    echo ""
} > $RECURSION_FILE

RECURSION_ALLOWED=false
SUCCESSFUL_QUERIES=0
TOTAL_QUERIES=0

# 간소화된 레코드 타입 (nslookup 호환성)
RECORD_TYPES=("A" "MX" "NS")

for domain in "${TEST_DOMAINS[@]}"; do
    for record_type in "${RECORD_TYPES[@]}"; do
        TOTAL_QUERIES=$((TOTAL_QUERIES + 1))
        echo "Testing: $domain $record_type" >> $RECURSION_FILE
        
        RESULT=$(query_dns "$domain" "$record_type" "$DNS_IP")
        echo "Result: $RESULT" >> $RECURSION_FILE
        
        # 성공적인 응답 확인 (QUERY_FAILED가 아닌 경우)
        if [[ "$RESULT" != "QUERY_FAILED" && -n "$RESULT" ]]; then
            SUCCESSFUL_QUERIES=$((SUCCESSFUL_QUERIES + 1))
            RECURSION_ALLOWED=true
            echo "SUCCESS: Got answer for $domain $record_type" >> $RECURSION_FILE
        else
            echo "FAILED: No answer for $domain $record_type" >> $RECURSION_FILE
        fi
        echo "---" >> $RECURSION_FILE
    done
done

# 4. DNS 증폭 공격 테스트 (단순화)
echo "INFO: Testing DNS amplification potential..."
AMPLIFICATION_FILE="$ARTIFACTS_DIR/dns_amplification_$ATTACK_ID.txt"
{
    echo "===== DNS Amplification Test ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo "Testing large response queries..."
    echo ""
} > $AMPLIFICATION_FILE

AMPLIFICATION_POTENTIAL=false

# 루트 도메인과 TLD에 대한 NS 쿼리 (큰 응답 유도)
for domain in "." "com" "net"; do
    echo "Testing NS query for: $domain" >> $AMPLIFICATION_FILE
    
    NS_RESULT=$(query_dns "$domain" "NS" "$DNS_IP")
    echo "NS Result: $NS_RESULT" >> $AMPLIFICATION_FILE
    
    # 응답 크기 대략적 추정 (다중 레코드가 있으면 증폭 가능성)
    if [[ "$NS_RESULT" != "QUERY_FAILED" ]]; then
        RESPONSE_LINES=$(echo "$NS_RESULT" | wc -l)
        if [ "$RESPONSE_LINES" -gt 3 ]; then
            AMPLIFICATION_POTENTIAL=true
            echo "LARGE RESPONSE: Multiple NS records for $domain (${RESPONSE_LINES} lines)" >> $AMPLIFICATION_FILE
        fi
    fi
    echo "---" >> $AMPLIFICATION_FILE
done

# 5. DNS 설정 정보 수집
echo "INFO: Gathering DNS server information..."
DNS_INFO_FILE="$ARTIFACTS_DIR/dns_info_$ATTACK_ID.txt"
{
    echo "===== DNS Server Information ====="
    echo "Timestamp: $(date)"
    echo "DNS Tool: $DNS_TOOL"
    echo ""
    
    # 버전 정보 시도 (CHAOS 클래스는 nslookup에서 제한적)
    echo "=== Version Query ==="
    if [[ "$DNS_TOOL" == "dig" ]]; then
        timeout $TIMEOUT dig @$DNS_IP version.bind CHAOS TXT 2>&1 || echo "Version query failed"
    else
        echo "Version query not supported with $DNS_TOOL"
    fi
    echo ""
    
    # 루트 서버 질의
    echo "=== Root Servers ==="
    ROOT_RESULT=$(query_dns "." "NS" "$DNS_IP")
    echo "Root NS Result: $ROOT_RESULT"
    echo ""
    
} > $DNS_INFO_FILE

# 6. 결과 분석 및 요약
echo "INFO: Analyzing DNS attack results..."
SUMMARY_FILE="$ARTIFACTS_DIR/dns_recursion_summary_$ATTACK_ID.txt"
{
    echo "===== DNS Recursion Attack Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "Target DNS: $DNS_IP:$DNS_PORT"
    echo "DNS Tool Used: $DNS_TOOL"
    echo "Timestamp: $(date)"
    echo ""
    
    echo "Test Results:"
    echo "- Total queries attempted: $TOTAL_QUERIES"
    echo "- Successful recursive queries: $SUCCESSFUL_QUERIES"
    echo "- Recursion allowed: $RECURSION_ALLOWED"
    echo "- Amplification potential: $AMPLIFICATION_POTENTIAL"
    echo ""
    
    # 보안 평가
    if [ "$RECURSION_ALLOWED" = true ]; then
        echo "SECURITY ASSESSMENT: VULNERABLE"
        echo "- DNS server allows recursive queries"
        echo "- Can be used for DNS amplification attacks"
        echo "- Risk of being abused as open resolver"
        
        if [ "$AMPLIFICATION_POTENTIAL" = true ]; then
            echo "- HIGH RISK: Large responses detected (amplification factor)"
        fi
        
        echo ""
        echo "Attack Scenarios:"
        echo "1. DNS Amplification DDoS:"
        echo "   - Attacker spoofs victim's IP"
        echo "   - Sends small DNS queries to this server"
        echo "   - Server responds with large replies to victim"
        echo "2. DNS Cache Poisoning:"
        echo "   - Pollute DNS cache with malicious records"
        echo "3. Information Disclosure:"
        echo "   - Enumerate internal network information"
        
    else
        echo "SECURITY ASSESSMENT: SECURE"
        echo "- DNS server properly restricts recursive queries"
        echo "- Protected against DNS amplification attacks"
    fi
    
    echo ""
    echo "Recommendations:"
    if [ "$RECURSION_ALLOWED" = true ]; then
        echo "- Disable recursion for external clients"
        echo "- Implement access control lists (ACLs)"
        echo "- Limit recursion to trusted networks only"
        echo "- Enable response rate limiting (RRL)"
        echo "- Monitor for suspicious query patterns"
    else
        echo "- Current configuration is secure"
        echo "- Continue monitoring DNS traffic"
    fi
    
    echo ""
    echo "Note: Analysis performed with $DNS_TOOL due to tool availability"
    echo ""
    echo "Artifacts generated:"
    echo "- Basic queries: dns_basic_$ATTACK_ID.txt"
    echo "- Recursion test: dns_recursion_$ATTACK_ID.txt"
    echo "- Amplification test: dns_amplification_$ATTACK_ID.txt"
    echo "- DNS info: dns_info_$ATTACK_ID.txt"
    echo "- Summary: dns_recursion_summary_$ATTACK_ID.txt"
    
} > $SUMMARY_FILE

echo "INFO: DNS recursion attack completed. Summary:"
cat $SUMMARY_FILE

exit 0
