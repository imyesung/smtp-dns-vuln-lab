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

# 외부 테스트용 도메인들 (실제로는 응답하지 않을 것이지만 재귀 질의 테스트용)
TEST_DOMAINS=(
    "google.com"
    "cloudflare.com"
    "microsoft.com"
    "github.com"
    "stackoverflow.com"
)

# DNS 레코드 타입들
RECORD_TYPES=(
    "A"
    "AAAA"
    "MX"
    "TXT"
    "NS"
    "SOA"
)

echo "INFO: Starting DNS recursion attack - ID: $ATTACK_ID"
echo "INFO: Target DNS: $DNS_TARGET ($DNS_IP:$DNS_PORT)"

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
    echo ""
} > $ARTIFACTS_DIR/dns_basic_$ATTACK_ID.txt

# 로컬 도메인 질의 (정상 동작 확인)
echo "INFO: Querying local domain..."
dig @$DNS_IP localhost A +short >> $ARTIFACTS_DIR/dns_basic_$ATTACK_ID.txt 2>&1 || echo "FAILED: localhost query" >> $ARTIFACTS_DIR/dns_basic_$ATTACK_ID.txt

# 3. 재귀 질의 테스트 (외부 도메인)
echo "INFO: Testing recursive queries for external domains..."
RECURSION_FILE="$ARTIFACTS_DIR/dns_recursion_$ATTACK_ID.txt"
{
    echo "===== DNS Recursion Test ====="
    echo "Timestamp: $(date)"
    echo "Testing external domain resolution..."
    echo ""
} > $RECURSION_FILE

RECURSION_ALLOWED=false
SUCCESSFUL_QUERIES=0
TOTAL_QUERIES=0

for domain in "${TEST_DOMAINS[@]}"; do
    for record_type in "${RECORD_TYPES[@]}"; do
        TOTAL_QUERIES=$((TOTAL_QUERIES + 1))
        echo "Testing: $domain $record_type" >> $RECURSION_FILE
        
        # dig 명령으로 재귀 질의 시도
        if timeout $TIMEOUT dig @$DNS_IP $domain $record_type +recurse +time=5 >> $RECURSION_FILE 2>&1; then
            # 응답에 ANSWER section이 있는지 확인
            if tail -20 $RECURSION_FILE | grep -q "ANSWER SECTION" || tail -20 $RECURSION_FILE | grep -q "status: NOERROR"; then
                SUCCESSFUL_QUERIES=$((SUCCESSFUL_QUERIES + 1))
                RECURSION_ALLOWED=true
                echo "SUCCESS: Got answer for $domain $record_type" >> $RECURSION_FILE
            else
                echo "FAILED: No answer for $domain $record_type" >> $RECURSION_FILE
            fi
        else
            echo "TIMEOUT/ERROR: Query failed for $domain $record_type" >> $RECURSION_FILE
        fi
        echo "---" >> $RECURSION_FILE
    done
done

# 4. DNS 증폭 공격 테스트
echo "INFO: Testing DNS amplification potential..."
AMPLIFICATION_FILE="$ARTIFACTS_DIR/dns_amplification_$ATTACK_ID.txt"
{
    echo "===== DNS Amplification Test ====="
    echo "Timestamp: $(date)"
    echo "Testing large response queries..."
    echo ""
} > $AMPLIFICATION_FILE

# ANY 쿼리 (큰 응답 유도)
AMPLIFICATION_POTENTIAL=false
for domain in "." "com" "net" "org"; do
    echo "Testing ANY query for: $domain" >> $AMPLIFICATION_FILE
    if timeout $TIMEOUT dig @$DNS_IP $domain ANY +bufsize=4096 >> $AMPLIFICATION_FILE 2>&1; then
        # 응답 크기 확인
        RESPONSE_SIZE=$(tail -50 $AMPLIFICATION_FILE | grep -o "MSG SIZE.*rcvd: [0-9]*" | tail -1 | grep -o "[0-9]*$")
        if [ -n "$RESPONSE_SIZE" ] && [ "$RESPONSE_SIZE" -gt 512 ]; then
            AMPLIFICATION_POTENTIAL=true
            echo "LARGE RESPONSE: $RESPONSE_SIZE bytes for $domain ANY" >> $AMPLIFICATION_FILE
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
    echo ""
    
    # 버전 정보 시도
    echo "=== Version Query ==="
    timeout $TIMEOUT dig @$DNS_IP version.bind CHAOS TXT 2>&1 || echo "Version query failed"
    echo ""
    
    # 호스트명 정보 시도
    echo "=== Hostname Query ==="
    timeout $TIMEOUT dig @$DNS_IP hostname.bind CHAOS TXT 2>&1 || echo "Hostname query failed"
    echo ""
    
    # 루트 서버 질의
    echo "=== Root Servers ==="
    timeout $TIMEOUT dig @$DNS_IP . NS 2>&1 || echo "Root NS query failed"
    echo ""
} > $DNS_INFO_FILE

# 6. 결과 분석 및 요약
echo "INFO: Analyzing DNS attack results..."
SUMMARY_FILE="$ARTIFACTS_DIR/dns_recursion_summary_$ATTACK_ID.txt"
{
    echo "===== DNS Recursion Attack Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "Target DNS: $DNS_IP:$DNS_PORT"
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
    echo "Artifacts generated:"
    echo "- Basic queries: dns_basic_$ATTACK_ID.txt"
    echo "- Recursion test: dns_recursion_$ATTACK_ID.txt"
    echo "- Amplification test: dns_amplification_$ATTACK_ID.txt"
    echo "- DNS info: dns_info_$ATTACK_ID.txt"
    echo "- Summary: dns_recursion_summary_$ATTACK_ID.txt"
    
} > $SUMMARY_FILE

echo "INFO: DNS recursion attack completed. Summary:"
cat $SUMMARY_FILE

# 7. 상세 결과 표시
echo ""
echo "===== Detailed Results ====="
echo "Successful recursive queries: $SUCCESSFUL_QUERIES/$TOTAL_QUERIES"

if [ $SUCCESSFUL_QUERIES -gt 0 ]; then
    echo ""
    echo "Sample successful queries:"
    grep -A 2 -B 1 "SUCCESS:" $RECURSION_FILE | head -20
fi

exit 0
