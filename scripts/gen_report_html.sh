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

# HTML 특수문자 이스케이프 함수
escape_html() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# 파일 존재 확인 및 내용 읽기 함수
read_analysis_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "<p><strong>오류:</strong> 분석 파일 '$file_path'을(를) 찾을 수 없습니다.</p>"
    else
        # Markdown 코드 블록을 HTML <pre>로 간단히 변환 (```text ... ``` -> <pre>...</pre>)
        # 실제 Markdown 변환기가 있다면 더 정교하게 처리 가능
        sed -e 's/^```text$/<pre>/g' -e 's/^```json$/<pre class="json">/g' -e 's/^```$/<\/pre>/g' "$file_path" | escape_html_except_pre
    fi
}

# <pre> 태그 내부를 제외하고 HTML 이스케이프 (sed 복잡성으로 인해 여기서는 전체 이스케이프 후 <pre>만 복원 시도 - 단순화)
# 실제로는 <pre> 내부 컨텐츠는 이미 tshark 등이 생성한 텍스트이므로, 전체를 escape_html로 처리하는 것이 안전할 수 있음
# 여기서는 read_analysis_file 내에서 sed로 ```를 <pre>로 바꾸고, 그 결과를 escape_html로 넘기는 대신,
# <pre> 태그 자체는 유지하고 그 안의 내용만 이스케이프하는 것이 이상적이나, bash만으로는 복잡.
# 여기서는 파일 전체를 escape_html 처리하고, <pre> 태그는 수동으로 생성.
# 분석 파일 내용 로드
BEFORE_CONTENT_HTML="<p>강화 전 분석 파일($BEFORE_ANALYSIS_FILE)을 찾을 수 없습니다.</p>"
if [ -f "$BEFORE_ANALYSIS_FILE" ]; then
    BEFORE_CONTENT_HTML=$(cat "$BEFORE_ANALYSIS_FILE" | escape_html | sed 's_&lt;br&gt;_<br>_g' | awk '{gsub(/```json/, "<pre class=\"json\">"); gsub(/```/, "</pre>"); print}')
    # ```text 또는 ```json 같은 마크다운 코드 블록을 <pre>로 변환하는 로직 추가 필요 시
fi

AFTER_CONTENT_HTML="<p>강화 후 분석 파일($AFTER_ANALYSIS_FILE)을 찾을 수 없습니다.</p>"
if [ -f "$AFTER_ANALYSIS_FILE" ]; then
    AFTER_CONTENT_HTML=$(cat "$AFTER_ANALYSIS_FILE" | escape_html | sed 's_&lt;br&gt;_<br>_g' | awk '{gsub(/```json/, "<pre class=\"json\">"); gsub(/```/, "</pre>"); print}')
fi

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

# 강화 전/후 판단 로직 추가
BEFORE_SMTP_CMDS_COUNT=$(grep -c "MAIL FROM\|RCPT TO\|DATA" "$BEFORE_ANALYSIS_FILE" || echo "0")
AFTER_SMTP_CMDS_COUNT=$(grep -c "MAIL FROM\|RCPT TO\|DATA" "$AFTER_ANALYSIS_FILE" || echo "0")

if [ "$BEFORE_SMTP_CMDS_COUNT" -gt 0 ] && [ "$AFTER_SMTP_CMDS_COUNT" -eq 0 ]; then
    VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 보안 강화 성공!</b> 강화 전에는 취약했으나 강화 후 보호됨</p>"
elif [ "$BEFORE_SMTP_CMDS_COUNT" -eq 0 ]; then
    VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 테스트 오류 가능성</b> 강화 전 테스트에서 SMTP 명령이 감지되지 않음</p>"
else
    VERDICT="<p class='failure' style='color:red; font-weight:bold;'><b>❌ 보안 강화 실패</b> 강화 후에도 메일 명령 실행 가능</p>"
fi

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="utf-8">
    <title>SMTP/DNS 취약점 분석 보고서 - $RUN_ID</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f4f4f4; color: #333; }
        .container { width: 80%; margin: 20px auto; background-color: #fff; padding: 20px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1, h2, h3 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 5px; }
        h1 { font-size: 2em; text-align: center; color: #007bff; }
        h2 { font-size: 1.5em; margin-top: 30px; }
        h3 { font-size: 1.2em; margin-top: 20px; border-bottom: 1px solid #ccc; }
        pre { background-color: #e9ecef; padding: 15px; border-radius: 5px; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; border: 1px solid #ced4da; }
        pre.json { background-color: #fdf6e3; color: #657b83; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #007bff; color: white; }
        .summary p, .environment p { line-height: 1.6; }
        .diff-added { color: green; }
        .diff-removed { color: red; }
        .footer { text-align: center; margin-top: 30px; font-size: 0.9em; color: #777; }
        .success { color: #28a745; background-color: #d4edda; padding: 10px; border-radius: 5px; }
        .warning { color: #856404; background-color: #fff3cd; padding: 10px; border-radius: 5px; }
        .failure { color: #721c24; background-color: #f8d7da; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>SMTP/DNS 취약점 분석 보고서</h1>

        <div class="summary">
            <h2>개요</h2>
            <p><strong>실행 ID:</strong> $RUN_ID</p>
            <p><strong>보고서 생성 시간 (UTC):</strong> $GENERATED_AT</p>
            <p>이 보고서는 SMTP 서비스의 보안 강화 조치 전후의 네트워크 트래픽 및 설정 변경 사항을 분석합니다.</p>
        </div>

        <div class="environment">
            <h2>실행 환경</h2>
            <h3>Docker 컨테이너 상태</h3>
            <pre>$DOCKER_PS_OUTPUT</pre>
        </div>

        <div class="analysis-section">
            <h2>강화 전 분석 결과</h2>
            <p>파일: <code>$BEFORE_ANALYSIS_FILE</code></p>
            <div>$BEFORE_CONTENT_HTML</div>
        </div>

        <div class="analysis-section">
            <h2>강화 후 분석 결과</h2>
            <p>파일: <code>$AFTER_ANALYSIS_FILE</code></p>
            <div>$AFTER_CONTENT_HTML</div>
        </div>

        <div class="diff-section">
            <h2>분석 결과 비교 (Diff)</h2>
            <p>다음은 강화 전후 분석 파일 간의 차이점입니다. (<code>diff -u</code> 기준)</p>
            $DIFF_CONTENT_HTML
        </div>
        
        <div class="verdict">
            <h2>결론</h2>
            <p>보안 강화 조치 후의 변경 사항을 통해 취약점 개선 여부를 자동으로 판단합니다:</p>
            $VERDICT
            
            <h3>주요 판단 기준</h3>
            <ul>
                <li>강화 전: MAIL FROM, RCPT TO, DATA 명령 감지 여부 (이메일 전송 시도)</li>
                <li>강화 후: 위 명령어가 차단되는지 확인</li>
            </ul>
            
            <p><small>참고: 이 판단은 SMTP 패킷 캡처에 기반합니다. 시스템 구성에 따라 추가적인 검토가 필요할 수 있습니다.</small></p>
        </div>

        <div class="footer">
            <p>SMTP/DNS Vulnerability Lab Report Generator</p>
        </div>
    </div>
</body>
</html>
EOF

echo "INFO: HTML 보고서 생성 완료: $REPORT_FILE"
# 운영체제에 따라 자동으로 브라우저에서 열기 (선택 사항)
xdg-open "$REPORT_FILE" 2>/dev/null || open "$REPORT_FILE" 2>/dev/null || echo "INFO: 브라우저에서 $REPORT_FILE 파일을 수동으로 열어주세요."

exit 0