#!/bin/bash

# PCAP 파일에서 SMTP 명령어 추출 스크립트
# analyze_pcap.sh - SMTP 패킷 캡처 파일에서 SMTP 명령어 및 응답 추출

# 사용법 검사
if [ $# -lt 1 ]; then
    echo "사용법: $0 <pcap_파일> [결과_파일]"
    echo "예: $0 /artifacts/smtp_ORT-20250508_123456.pcap /artifacts/analysis_ORT-20250508_123456.txt"
    exit 1
fi

# 인자 처리
PCAP_FILE="$1"
OUTPUT_FILE="${2:-${PCAP_FILE%.*}_analysis.txt}"  # 기본값: 원본 파일명에 _analysis 접미사 추가
ATTACK_ID=$(basename "$PCAP_FILE" | grep -oP 'ORT-[0-9_]+' || echo "UNKNOWN")
CURRENT_ISO_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 필요한 도구 확인
command -v tshark >/dev/null 2>&1 || { echo "오류: tshark가 필요합니다. apt-get install tshark로 설치하세요."; exit 2; }

# 결과 파일 헤더 작성
cat > "$OUTPUT_FILE" <<EOF
# SMTP 패킷 분석 보고서
- 분석 시간: $CURRENT_ISO_TIMESTAMP
- 공격 ID: $ATTACK_ID
- 분석 파일: $PCAP_FILE

## SMTP 명령 및 응답 시퀀스
\`\`\`
EOF

# SMTP 명령과 응답 추출 (포트 25, 465, 587)
echo "SMTP 명령어 및 응답 추출 중..."
tshark -r "$PCAP_FILE" -Y "smtp" -T fields -e frame.time_relative -e ip.src -e ip.dst -e smtp.req.command -e smtp.req.parameter -e smtp.response.code -e smtp.response.parameter -E header=y -E separator=" | " -E quote=n | sort -n >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "\`\`\`" >> "$OUTPUT_FILE"

# 메일 내용 추출 (DATA 명령 이후의 내용)
echo -e "\n## 메일 내용 (있는 경우)\n\`\`\`" >> "$OUTPUT_FILE"
tshark -r "$PCAP_FILE" -Y "smtp.data.fragment" -T fields -e smtp.data.fragment -E header=n -E quote=n >> "$OUTPUT_FILE"
echo -e "\`\`\`\n" >> "$OUTPUT_FILE"

# 메타데이터 통계 추가
echo -e "## 메타데이터 및 통계\n" >> "$OUTPUT_FILE"
TOTAL_PKTS=$(tshark -r "$PCAP_FILE" -T fields | wc -l)
SMTP_PKTS=$(tshark -r "$PCAP_FILE" -Y "smtp" -T fields | wc -l)
SMTP_CMDS=$(tshark -r "$PCAP_FILE" -Y "smtp.req.command" -T fields -e smtp.req.command | sort | uniq -c | sort -nr)

echo "- 총 패킷 수: $TOTAL_PKTS" >> "$OUTPUT_FILE"
echo "- SMTP 관련 패킷 수: $SMTP_PKTS" >> "$OUTPUT_FILE"
echo -e "\n### SMTP 명령어 통계:\n\`\`\`" >> "$OUTPUT_FILE"
echo "$SMTP_CMDS" >> "$OUTPUT_FILE"
echo -e "\`\`\`" >> "$OUTPUT_FILE"

# JSON 형식의 요약 정보도 추가
SUMMARY_JSON=$(cat <<EOF
{
    "event_type": "smtp_analysis",
    "attack_id": "$ATTACK_ID",
    "timestamp_utc": "$CURRENT_ISO_TIMESTAMP",
    "pcap_file": "$PCAP_FILE",
    "output_file": "$OUTPUT_FILE",
    "total_packets": $TOTAL_PKTS,
    "smtp_packets": $SMTP_PKTS
}
EOF
)

echo -e "\n## JSON 요약\n\`\`\`json" >> "$OUTPUT_FILE"
echo "$SUMMARY_JSON" >> "$OUTPUT_FILE"
echo -e "\`\`\`" >> "$OUTPUT_FILE"

echo "분석 완료: $OUTPUT_FILE"
exit 0