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
# 분석 파일 내용 로드 (더 나은 포맷팅)
format_analysis_content() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "<p>분석 파일을 찾을 수 없습니다: $file_path</p>"
        return
    fi
    
    # 텍스트를 읽어서 적절히 포맷팅
    cat "$file_path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | \
    sed 's/^#\(.*\)$/<h4>\1<\/h4>/g' | \
    sed 's/^총 패킷 수:/<strong>총 패킷 수:<\/strong>/g' | \
    sed 's/^파일 크기:/<strong>파일 크기:<\/strong>/g' | \
    sed 's/^실행 ID:/<strong>실행 ID:<\/strong>/g' | \
    sed 's/^분석 파일:/<strong>분석 파일:<\/strong>/g' | \
    sed 's/^SMTP 관련 패킷 수:/<strong>SMTP 관련 패킷 수:<\/strong>/g' | \
    sed 's/^SMTP 응답 코드:/<strong>SMTP 응답 코드:<\/strong>/g' | \
    sed 's/^SMTP 트래픽 ===/\<hr\>\<h5\>SMTP 트래픽 분석\<\/h5\>/g' | \
    sed 's/^메일 내용 (있는 경우)/<h5>메일 내용<\/h5>/g' | \
    sed 's/^JSON 요약$/<h5>JSON 요약<\/h5>/g' | \
    sed 's/^```json$/<pre class="json">/g' | \
    sed 's/^```$/<\/pre>/g' | \
    sed 's/$/\<br\>/g' | \
    sed 's/\<br\>\<\/pre\>/<\/pre>/g' | \
    sed 's/\<pre class="json"\>\<br\>/<pre class="json">/g'
}

BEFORE_CONTENT_HTML=$(format_analysis_content "$BEFORE_ANALYSIS_FILE")
AFTER_CONTENT_HTML=$(format_analysis_content "$AFTER_ANALYSIS_FILE")

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

# 숫자 비교 및 판단 로직 (개선된 버전 - 더 정교한 분석)
if [[ "$before_packets" =~ ^[0-9]+$ ]] && [[ "$after_packets" =~ ^[0-9]+$ ]]; then
    # 패킷 수 차이 계산
    packet_diff=$((before_packets - after_packets))
    
    # 동적 임계값 설정 (패킷 수에 따라 조정)
    if [ "$before_packets" -lt 50 ]; then
        # 작은 패킷 수: 최소 5개 또는 15% 감소
        min_meaningful_diff=5
        min_percent_change=15
    elif [ "$before_packets" -lt 200 ]; then
        # 중간 패킷 수: 최소 8개 또는 10% 감소  
        min_meaningful_diff=8
        min_percent_change=10
    else
        # 큰 패킷 수: 최소 15개 또는 8% 감소
        min_meaningful_diff=15
        min_percent_change=8
    fi
    
    if [ "$before_packets" -gt 0 ]; then
        percent_change=$(( (packet_diff * 100) / before_packets ))
    else
        percent_change=0
    fi
    
    # 보안 강화 효과성 평가
    if [ "$packet_diff" -ge "$min_meaningful_diff" ] && [ "$percent_change" -ge "$min_percent_change" ]; then
        PACKET_VERDICT="<p class='success' style='color:green; font-weight:bold;'><b>✅ 유의미한 트래픽 감소!</b> 패킷 수 $percent_change% 감소 ($before_packets → $after_packets, -$packet_diff 패킷)</p>"
    elif [ "$packet_diff" -gt 0 ] && [ "$packet_diff" -ge 3 ] && [ "$percent_change" -ge 2 ]; then
        # 소폭 감소도 긍정적으로 평가 (SMTP 세션 특성상)
        PACKET_VERDICT="<p class='partial-success' style='color:#ff8c00; font-weight:bold;'><b>🔶 경미한 트래픽 감소</b> 패킷 수 $percent_change% 감소 ($before_packets → $after_packets, -$packet_diff 패킷) - SMTP 세션 최적화 효과</p>"
    elif [ "$packet_diff" -gt 0 ] && [ "$packet_diff" -lt 3 ]; then
        PACKET_VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 미미한 트래픽 변화</b> 패킷 수 소폭 감소 ($before_packets → $after_packets, -$packet_diff 패킷) - TCP 핸드셰이크 차이 수준</p>"
    elif [ "$before_packets" -eq "$after_packets" ]; then
        PACKET_VERDICT="<p class='warning' style='color:orange; font-weight:bold;'><b>⚠️ 트래픽 변화 없음</b> 강화 전후 패킷 수 동일 ($before_packets) - 응답 코드 분석 필요</p>"
    else
        traffic_increase=$((after_packets - before_packets))
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
                        <div class="metric-change $([ $((after_packets - before_packets)) -lt 0 ] && echo 'change-positive' || [ $((after_packets - before_packets)) -gt 0 ] && echo 'change-negative' || echo 'change-neutral')">
                            $([ $((after_packets - before_packets)) -eq 0 ] && echo '변화 없음' || echo "$((after_packets - before_packets)) 패킷")
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
                            <td style="color: $([ $((after_packets - before_packets)) -lt 0 ] && echo 'var(--success-green)' || [ $((after_packets - before_packets)) -gt 0 ] && echo 'var(--error-red)' || echo 'var(--text-light)');">
                                $(( after_packets - before_packets ))
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
                📊 실행 환경 및 Docker 컨테이너 상태
            </div>
            <div class="collapsible-content">
                <pre>$DOCKER_PS_OUTPUT</pre>
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                🔍 강화 전후 분석 결과 비교 (Diff)
            </div>
            <div class="collapsible-content">
                <p>다음은 강화 전후 분석 파일 간의 차이점입니다.</p>
                $DIFF_CONTENT_HTML
            </div>
        </div>

        <div class="collapsible">
            <div class="collapsible-header">
                📋 판단 기준 및 해석 가이드
            </div>
            <div class="collapsible-content">
                <h4>보안 점수 기준</h4>
                <ul>
                    <li><strong>강력한 보안 강화 (70점+):</strong> 다층적 보안 개선 - 거부 응답 증가 + DATA 명령 차단 + 인증 강화</li>
                    <li><strong>보안 강화 성공 (40-69점):</strong> 핵심 보안 지표 개선 - 5xx 거부 응답 증가 또는 DATA 명령 차단</li>
                    <li><strong>부분적 개선 (20-39점):</strong> 일부 보안 요소 개선되나 추가 조치 필요</li>
                    <li><strong>강화 실패 (0-19점):</strong> 거부 응답 증가 없이 공격 명령 여전히 실행 가능</li>
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
            자동화된 보안 분석 도구로 생성됨</p>
        </div>
    </div>
</body>
</html>
EOF

echo "INFO: HTML 보고서 생성 완료: $REPORT_FILE"
# 운영체제에 따라 자동으로 브라우저에서 열기 (선택 사항)
xdg-open "$REPORT_FILE" 2>/dev/null || open "$REPORT_FILE" 2>/dev/null || echo "INFO: 브라우저에서 $REPORT_FILE 파일을 수동으로 열어주세요."

exit 0