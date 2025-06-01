#!/bin/bash
# scripts/gen_report_html.sh

# 사용법 검사
if [ "$#" -ne 4 ]; then
    echo "사용법: $0 <실행_ID> <강화_전_분석_파일> <강화_후_분석_파일> <아티팩트_디렉토리>" >&2
    exit 1
fi

RUN_ID_ARG="$1"
BEFORE_ANALYSIS_FILE="$2"
AFTER_ANALYSIS_FILE="$3"
ARTIFACTS_DIR_ARG="$4"

# --- DEBUG START ---
echo "DEBUG: Passed RUN_ID_ARG (Arg 1) = [$RUN_ID_ARG]"
echo "DEBUG: Passed ARTIFACTS_DIR_ARG (Arg 4) = [$ARTIFACTS_DIR_ARG]"
# --- DEBUG END ---

# ARTIFACTS_DIR_ARG가 비어있는지 확인
if [ -z "$ARTIFACTS_DIR_ARG" ]; then
    echo "ERROR: ARTIFACTS_DIR 인자가 비어있습니다." >&2
    exit 1
fi
# RUN_ID_ARG가 비어있는지 확인
if [ -z "$RUN_ID_ARG" ]; then
    echo "ERROR: RUN_ID 인자가 비어있습니다." >&2
    exit 1
fi

REPORT_FILE="${ARTIFACTS_DIR_ARG}/security_report_${RUN_ID_ARG}.html"

# --- DEBUG START ---
echo "DEBUG: Constructed REPORT_FILE = [$REPORT_FILE]"
# --- DEBUG END ---

# ARTIFACTS_DIR_ARG 디렉토리가 실제로 존재하는지 확인
if [ ! -d "$ARTIFACTS_DIR_ARG" ]; then
    echo "ERROR: ARTIFACTS_DIR '$ARTIFACTS_DIR_ARG'가 존재하지 않거나 디렉토리가 아닙니다." >&2
    # 필요하다면 여기서 exit 또는 디렉토리 생성 로직 추가
    # Makefile에서 ./artifacts 디렉토리를 미리 생성해야 합니다.
    # mkdir -p "$ARTIFACTS_DIR_ARG" # 또는 스크립트에서 생성
fi

# REPORT_FILE 초기화
> "$REPORT_FILE"

# HTML 특수문자 이스케이프 함수
escape_html() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# 분석 파일 처리
BEFORE_CONTENT_HTML="<div class='no-data'>강화 전 분석 파일을 찾을 수 없습니다.</div>"
if [ -f "$BEFORE_ANALYSIS_FILE" ]; then
    BEFORE_CONTENT_HTML="<pre class='code-block'>$(cat "$BEFORE_ANALYSIS_FILE" | escape_html)</pre>"
fi

AFTER_CONTENT_HTML="<div class='no-data'>강화 후 분석 파일을 찾을 수 없습니다.</div>"
if [ -f "$AFTER_ANALYSIS_FILE" ]; then
    AFTER_CONTENT_HTML="<pre class='code-block'>$(cat "$AFTER_ANALYSIS_FILE" | escape_html)</pre>"
fi

# 포트별 분석 (개행 문자 제거)
BEFORE_PORT25_COUNT=0
BEFORE_PORT587_COUNT=0
AFTER_PORT25_COUNT=0
AFTER_PORT587_COUNT=0

if [ -f "$BEFORE_ANALYSIS_FILE" ]; then
    BEFORE_PORT25_COUNT=$(grep -c "25.*MAIL FROM\|25.*RCPT TO\|25.*DATA" "$BEFORE_ANALYSIS_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    BEFORE_PORT587_COUNT=$(grep -c "587.*MAIL FROM\|587.*RCPT TO\|587.*DATA" "$BEFORE_ANALYSIS_FILE" 2>/dev/null | tr -d '\n' || echo "0")
fi

if [ -f "$AFTER_ANALYSIS_FILE" ]; then
    AFTER_PORT25_COUNT=$(grep -c "25.*MAIL FROM\|25.*RCPT TO\|25.*DATA" "$AFTER_ANALYSIS_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    AFTER_PORT587_COUNT=$(grep -c "587.*MAIL FROM\|587.*RCPT TO\|587.*DATA" "$AFTER_ANALYSIS_FILE" 2>/dev/null | tr -d '\n' || echo "0")
fi

# 정수 값으로 변환 (안전성 체크)
BEFORE_PORT25_COUNT=${BEFORE_PORT25_COUNT:-0}
BEFORE_PORT587_COUNT=${BEFORE_PORT587_COUNT:-0}
AFTER_PORT25_COUNT=${AFTER_PORT25_COUNT:-0}
AFTER_PORT587_COUNT=${AFTER_PORT587_COUNT:-0}

# 판정 로직
PORT25_VERDICT="⚠️ 불충분한 데이터"
PORT587_VERDICT="⚠️ 불충분한 데이터"

if [ "$BEFORE_PORT25_COUNT" -gt 0 ] && [ "$AFTER_PORT25_COUNT" -eq 0 ]; then
    PORT25_VERDICT="✅ 오픈 릴레이 차단 성공"
elif [ "$BEFORE_PORT25_COUNT" -gt 0 ] && [ "$AFTER_PORT25_COUNT" -gt 0 ]; then
    PORT25_VERDICT="❌ 오픈 릴레이 여전히 취약"
elif [ "$BEFORE_PORT25_COUNT" -eq 0 ]; then
    PORT25_VERDICT="⚠️ 강화 전 데이터 없음"
fi

if [ "$BEFORE_PORT587_COUNT" -gt 0 ] && [ "$AFTER_PORT587_COUNT" -eq 0 ]; then
    PORT587_VERDICT="✅ MSA 인증 강제화 성공"
elif [ "$BEFORE_PORT587_COUNT" -gt 0 ] && [ "$AFTER_PORT587_COUNT" -gt 0 ]; then
    PORT587_VERDICT="❌ MSA 여전히 취약"
elif [ "$BEFORE_PORT587_COUNT" -eq 0 ]; then
    PORT587_VERDICT="⚠️ 강화 전 데이터 없음"
fi

cat > "$REPORT_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SMTP Security Analysis Report</title>
    <style>
        /* Dark Theme - Fixed CSS */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            line-height: 1.5;
            font-size: 14px;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 24px;
        }

        /* Header */
        .header {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 24px;
            margin-bottom: 24px;
        }

        .header h1 {
            font-size: 32px;
            font-weight: 600;
            color: #c9d1d9;
            margin-bottom: 8px;
        }

        .header .subtitle {
            color: #8b949e;
            font-size: 16px;
        }

        .header .meta {
            margin-top: 16px;
            display: flex;
            flex-wrap: wrap;
            gap: 16px;
        }

        .meta-item {
            background: #21262d;
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 12px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
        }

        /* Cards */
        .card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 24px;
            margin-bottom: 24px;
        }

        .card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 16px;
            padding-bottom: 16px;
            border-bottom: 1px solid #21262d;
        }

        .card-title {
            font-size: 20px;
            font-weight: 600;
            color: #c9d1d9;
        }

        .badge {
            padding: 4px 8px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 500;
            text-transform: uppercase;
        }

        .badge.success { background: #3fb950; color: #000; }
        .badge.warning { background: #d29922; color: #000; }
        .badge.danger { background: #f85149; color: #fff; }
        .badge.info { background: #58a6ff; color: #fff; }

        /* Status Cards */
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }

        .status-card {
            background: #21262d;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 20px;
            text-align: center;
        }

        .status-icon {
            font-size: 32px;
            margin-bottom: 12px;
        }

        .status-title {
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .status-value {
            font-size: 18px;
            font-weight: 700;
        }

        /* Code blocks */
        .code-block {
            background: #0d1117;
            border: 1px solid #30363d;
            border-radius: 6px;
            padding: 16px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 12px;
            overflow-x: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
            color: #c9d1d9;
        }

        .no-data {
            background: #21262d;
            border: 1px dashed #30363d;
            border-radius: 6px;
            padding: 32px;
            text-align: center;
            color: #6e7681;
            font-style: italic;
        }

        /* Tabs */
        .tabs {
            display: flex;
            border-bottom: 1px solid #30363d;
            margin-bottom: 20px;
        }

        .tab {
            padding: 12px 16px;
            background: none;
            border: none;
            color: #8b949e;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            border-bottom: 2px solid transparent;
            transition: all 0.2s;
        }

        .tab.active {
            color: #58a6ff;
            border-bottom-color: #58a6ff;
        }

        .tab:hover {
            color: #c9d1d9;
        }

        .tab-content {
            display: none;
        }

        .tab-content.active {
            display: block;
        }

        .tab-content h3 {
            color: #c9d1d9;
            margin-bottom: 16px;
        }

        /* Analysis sections */
        .analysis-section {
            margin-bottom: 32px;
        }

        .comparison-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 16px;
        }

        .comparison-table th,
        .comparison-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #30363d;
        }

        .comparison-table th {
            background: #21262d;
            font-weight: 600;
            color: #c9d1d9;
        }

        .comparison-table td {
            color: #8b949e;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 12px;
        }

        /* Footer */
        .footer {
            margin-top: 48px;
            padding-top: 24px;
            border-top: 1px solid #30363d;
            text-align: center;
            color: #6e7681;
            font-size: 12px;
        }

        /* Responsive */
        @media (max-width: 768px) {
            .container { padding: 16px; }
            .header h1 { font-size: 24px; }
            .status-grid { grid-template-columns: 1fr; }
            .meta { flex-direction: column; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔐 SMTP Security Analysis</h1>
            <div class="subtitle">Multi-Port Vulnerability Assessment Report</div>
            <div class="meta">
                <div class="meta-item">RUN_ID_PLACEHOLDER</div>
                <div class="meta-item">GENERATED_AT_PLACEHOLDER</div>
                <div class="meta-item">PORTS: 25 (Relay) • 587 (MSA)</div>
            </div>
        </div>

        <div class="status-grid">
            <div class="status-card">
                <div class="status-icon">🔓</div>
                <div class="status-title">Port 25 (Open Relay)</div>
                <div class="status-value">PORT25_VERDICT_PLACEHOLDER</div>
            </div>
            <div class="status-card">
                <div class="status-icon">📧</div>
                <div class="status-title">Port 587 (MSA)</div>
                <div class="status-value">PORT587_VERDICT_PLACEHOLDER</div>
            </div>
        </div>

        <div class="card">
            <div class="card-header">
                <h2 class="card-title">📊 Analysis Results</h2>
                <span class="badge info">Dual Port</span>
            </div>
            
            <div class="tabs">
                <button class="tab active" onclick="showTab('before')">Before Hardening</button>
                <button class="tab" onclick="showTab('after')">After Hardening</button>
                <button class="tab" onclick="showTab('comparison')">Comparison</button>
            </div>

            <div id="before" class="tab-content active">
                <h3>Pre-Hardening Analysis</h3>
                <p style="color: #8b949e; margin-bottom: 16px;">
                    Analysis of SMTP traffic before security hardening measures.
                </p>
                BEFORE_CONTENT_PLACEHOLDER
            </div>

            <div id="after" class="tab-content">
                <h3>Post-Hardening Analysis</h3>
                <p style="color: #8b949e; margin-bottom: 16px;">
                    Analysis of SMTP traffic after security hardening measures.
                </p>
                AFTER_CONTENT_PLACEHOLDER
            </div>

            <div id="comparison" class="tab-content">
                <h3>Security Impact Assessment</h3>
                <table class="comparison-table">
                    <thead>
                        <tr>
                            <th>Metric</th>
                            <th>Before</th>
                            <th>After</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr>
                            <td>Port 25 SMTP Commands</td>
                            <td>BEFORE_PORT25_COUNT_PLACEHOLDER</td>
                            <td>AFTER_PORT25_COUNT_PLACEHOLDER</td>
                            <td><span class="badge">PORT25_VERDICT_PLACEHOLDER</span></td>
                        </tr>
                        <tr>
                            <td>Port 587 SMTP Commands</td>
                            <td>BEFORE_PORT587_COUNT_PLACEHOLDER</td>
                            <td>AFTER_PORT587_COUNT_PLACEHOLDER</td>
                            <td><span class="badge">PORT587_VERDICT_PLACEHOLDER</span></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <div class="footer">
            <p>🔬 SMTP/DNS Vulnerability Lab • Project Zero Inspired Design</p>
            <p>Generated by automated security assessment tools</p>
        </div>
    </div>

    <script>
        function showTab(tabName) {
            // Hide all tab contents
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.remove('active');
            });
            
            // Remove active class from all tabs
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });
            
            // Show selected tab content
            document.getElementById(tabName).classList.add('active');
            
            // Add active class to clicked tab
            event.target.classList.add('active');
        }
    </script>
</body>
</html>
EOF

# macOS 호환성을 위한 sed 옵션 (백업 확장자 없이)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/RUN_ID_PLACEHOLDER/$RUN_ID/g" "$REPORT_FILE"
    sed -i '' "s/GENERATED_AT_PLACEHOLDER/$GENERATED_AT/g" "$REPORT_FILE"
    sed -i '' "s/PORT25_VERDICT_PLACEHOLDER/$PORT25_VERDICT/g" "$REPORT_FILE"
    sed -i '' "s/PORT587_VERDICT_PLACEHOLDER/$PORT587_VERDICT/g" "$REPORT_FILE"
    sed -i '' "s/BEFORE_PORT25_COUNT_PLACEHOLDER/$BEFORE_PORT25_COUNT/g" "$REPORT_FILE"
    sed -i '' "s/AFTER_PORT25_COUNT_PLACEHOLDER/$AFTER_PORT25_COUNT/g" "$REPORT_FILE"
    sed -i '' "s/BEFORE_PORT587_COUNT_PLACEHOLDER/$BEFORE_PORT587_COUNT/g" "$REPORT_FILE"
    sed -i '' "s/AFTER_PORT587_COUNT_PLACEHOLDER/$AFTER_PORT587_COUNT/g" "$REPORT_FILE"
else
    # Linux
    sed -i "s/RUN_ID_PLACEHOLDER/$RUN_ID/g" "$REPORT_FILE"
    sed -i "s/GENERATED_AT_PLACEHOLDER/$GENERATED_AT/g" "$REPORT_FILE"
    sed -i "s/PORT25_VERDICT_PLACEHOLDER/$PORT25_VERDICT/g" "$REPORT_FILE"
    sed -i "s/PORT587_VERDICT_PLACEHOLDER/$PORT587_VERDICT/g" "$REPORT_FILE"
    sed -i "s/BEFORE_PORT25_COUNT_PLACEHOLDER/$BEFORE_PORT25_COUNT/g" "$REPORT_FILE"
    sed -i "s/AFTER_PORT25_COUNT_PLACEHOLDER/$AFTER_PORT25_COUNT/g" "$REPORT_FILE"
    sed -i "s/BEFORE_PORT587_COUNT_PLACEHOLDER/$BEFORE_PORT587_COUNT/g" "$REPORT_FILE"
    sed -i "s/AFTER_PORT587_COUNT_PLACEHOLDER/$AFTER_PORT587_COUNT/g" "$REPORT_FILE"
fi

# 안전한 콘텐츠 교체 (printf 사용)
# BEFORE_CONTENT 교체
printf '%s\n' "$(cat "$REPORT_FILE")" | awk -v replacement="$BEFORE_CONTENT_HTML" '{gsub(/BEFORE_CONTENT_PLACEHOLDER/, replacement); print}' > /tmp/temp_report_before.html
mv /tmp/temp_report_before.html "$REPORT_FILE"

# AFTER_CONTENT 교체
printf '%s\n' "$(cat "$REPORT_FILE")" | awk -v replacement="$AFTER_CONTENT_HTML" '{gsub(/AFTER_CONTENT_PLACEHOLDER/, replacement); print}' > /tmp/temp_report_after.html
mv /tmp/temp_report_after.html "$REPORT_FILE"

echo "INFO: SMTP Vulnerability HTML Report 생성 완료: $REPORT_FILE"
open "$REPORT_FILE" 2>/dev/null || xdg-open "$REPORT_FILE" 2>/dev/null || echo "INFO: 브라우저에서 $REPORT_FILE 파일을 수동으로 열어주세요."

exit 0