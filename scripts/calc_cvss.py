#!/usr/bin/env python3
"""
CVSS 3.1 자동 점수 산정 시스템
SMTP/DNS 취약점에 대한 CVSS 벡터 자동 계산 및 점수 산출
"""

import json
import sys
import argparse
import re
from datetime import datetime, timezone

class CVSSCalculator:
    def __init__(self):
        # CVSS 3.1 Base Metrics 점수 매핑
        self.base_metrics = {
            'AV': {'N': 0.85, 'A': 0.62, 'L': 0.55, 'P': 0.2},  # Attack Vector
            'AC': {'L': 0.77, 'H': 0.44},  # Attack Complexity
            'UI': {'N': 0.85, 'R': 0.62},  # User Interaction
            'C': {'N': 0.0, 'L': 0.22, 'H': 0.56},  # Confidentiality
            'I': {'N': 0.0, 'L': 0.22, 'H': 0.56},  # Integrity
            'A': {'N': 0.0, 'L': 0.22, 'H': 0.56}   # Availability
        }
        
        # Privileges Required - Scope 의존적 계수
        self.pr_values = {
            'U': {'N': 0.85, 'L': 0.62, 'H': 0.27},  # Unchanged
            'C': {'N': 0.85, 'L': 0.68, 'H': 0.50}   # Changed
        }
        
        # SMTP/DNS 특화 취약점 프로파일
        self.vulnerability_profiles = {
            'open_relay': {
                'AV': 'N',  # Network accessible
                'AC': 'L',  # Low complexity
                'PR': 'N',  # No privileges required
                'UI': 'N',  # No user interaction
                'S': 'U',   # Unchanged scope
                'C': 'N',   # No confidentiality impact (직접적으로)
                'I': 'H',   # High integrity impact (스팸/피싱)
                'A': 'L',   # Low availability impact
                'description': 'SMTP Open Relay - 무단 메일 전송 허용'
            },
            'starttls_downgrade': {
                'AV': 'N',  # Network attack
                'AC': 'H',  # High complexity (MITM required)
                'PR': 'N',  # No privileges
                'UI': 'N',  # No user interaction
                'S': 'U',   # Unchanged
                'C': 'H',   # High confidentiality impact
                'I': 'H',   # High integrity impact
                'A': 'N',   # No availability impact
                'description': 'STARTTLS Downgrade - 암호화 우회'
            },
            'dns_recursion': {
                'AV': 'N',  # Network
                'AC': 'L',  # Low complexity
                'PR': 'N',  # No privileges
                'UI': 'N',  # No interaction
                'S': 'U',   # Unchanged
                'C': 'N',   # No confidentiality impact
                'I': 'L',   # Low integrity (cache poisoning 가능)
                'A': 'H',   # High availability (DDoS amplification)
                'description': 'DNS Open Recursion - DDoS 증폭 공격 가능'
            },
            'plaintext_auth': {
                'AV': 'N',  # Network
                'AC': 'L',  # Low complexity
                'PR': 'N',  # No privileges
                'UI': 'N',  # No interaction
                'S': 'U',   # Unchanged
                'C': 'H',   # High confidentiality (credential exposure)
                'I': 'H',   # High integrity (account takeover)
                'A': 'N',   # No availability impact
                'description': 'Plaintext Authentication - 자격증명 노출'
            },
            'dane_mta_sts_bypass': {
                'AV': 'N',  # Network
                'AC': 'H',  # High complexity (complex setup)
                'PR': 'N',  # No privileges
                'UI': 'N',  # No interaction
                'S': 'C',   # Changed (bypassing security controls affects other components)
                'C': 'H',   # High confidentiality
                'I': 'H',   # High integrity
                'A': 'N',   # No availability
                'description': 'DANE/MTA-STS Bypass - 전송 보안 우회'
            }
        }

    def parse_vector_string(self, vector_string):
        """CVSS 벡터 문자열을 파싱하여 딕셔너리 반환"""
        if not vector_string.startswith('CVSS:3.1/'):
            raise ValueError("벡터 문자열은 'CVSS:3.1/'로 시작해야 합니다")
        
        vector_part = vector_string[9:]  # 'CVSS:3.1/' 제거
        pairs = vector_part.split('/')
        
        vector = {}
        required_metrics = ['AV', 'AC', 'PR', 'UI', 'S', 'C', 'I', 'A']
        
        for pair in pairs:
            if ':' not in pair:
                raise ValueError(f"잘못된 메트릭 형식: {pair}")
            key, value = pair.split(':', 1)
            vector[key] = value
        
        # 필수 메트릭 검증
        for metric in required_metrics:
            if metric not in vector:
                raise ValueError(f"필수 메트릭 누락: {metric}")
        
        # 값 유효성 검증
        valid_values = {
            'AV': ['N', 'A', 'L', 'P'],
            'AC': ['L', 'H'],
            'PR': ['N', 'L', 'H'],
            'UI': ['N', 'R'],
            'S': ['U', 'C'],
            'C': ['N', 'L', 'H'],
            'I': ['N', 'L', 'H'],
            'A': ['N', 'L', 'H']
        }
        
        for metric, value in vector.items():
            if metric in valid_values and value not in valid_values[metric]:
                raise ValueError(f"잘못된 {metric} 값: {value}")
        
        return vector

    def calculate_base_score(self, vector):
        """CVSS 3.1 Base Score 계산"""
        # Impact Sub-Score 계산
        isc_base = 1 - ((1 - self.base_metrics['C'][vector['C']]) * 
                       (1 - self.base_metrics['I'][vector['I']]) * 
                       (1 - self.base_metrics['A'][vector['A']]))
        
        if vector['S'] == 'U':
            impact = 6.42 * isc_base
        else:  # Scope Changed
            impact = 7.52 * (isc_base - 0.029) - 3.25 * pow(isc_base - 0.02, 15)
        
        # Exploitability Sub-Score 계산 (Scope 의존적 PR 계수 적용)
        pr = self.pr_values[vector['S']][vector['PR']]
        exploitability = (8.22 * 
                         self.base_metrics['AV'][vector['AV']] * 
                         self.base_metrics['AC'][vector['AC']] * 
                         pr * 
                         self.base_metrics['UI'][vector['UI']])
        
        # Base Score 계산
        if impact <= 0:
            base_score = 0.0
        else:
            if vector['S'] == 'U':
                base_score = min(impact + exploitability, 10.0)
            else:
                base_score = min(1.08 * (impact + exploitability), 10.0)
        
        return round(base_score, 1)

    def get_severity_rating(self, score):
        """CVSS 점수에 따른 심각도 등급 반환"""
        if score == 0.0:
            return "None"
        elif score <= 3.9:
            return "Low"
        elif score <= 6.9:
            return "Medium"
        elif score <= 8.9:
            return "High"
        else:
            return "Critical"

    def generate_vector_string(self, vector):
        """CVSS 벡터 문자열 생성"""
        return f"CVSS:3.1/AV:{vector['AV']}/AC:{vector['AC']}/PR:{vector['PR']}/UI:{vector['UI']}/S:{vector['S']}/C:{vector['C']}/I:{vector['I']}/A:{vector['A']}"

    def calculate_vulnerability(self, vuln_type):
        """특정 취약점 유형에 대한 CVSS 계산"""
        if vuln_type not in self.vulnerability_profiles:
            raise ValueError(f"Unknown vulnerability type: {vuln_type}")
        
        profile = self.vulnerability_profiles[vuln_type]
        vector = {k: v for k, v in profile.items() if k != 'description'}
        
        base_score = self.calculate_base_score(vector)
        severity = self.get_severity_rating(base_score)
        vector_string = self.generate_vector_string(vector)
        
        return {
            'vulnerability_type': vuln_type,
            'description': profile['description'],
            'cvss_vector': vector_string,
            'base_score': base_score,
            'severity': severity,
            'metrics': vector,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

    def calculate_from_vector(self, vector_string):
        """CVSS 벡터 문자열로부터 점수 계산"""
        vector = self.parse_vector_string(vector_string)
        base_score = self.calculate_base_score(vector)
        severity = self.get_severity_rating(base_score)
        
        return {
            'vulnerability_type': 'custom',
            'description': '사용자 정의 벡터',
            'cvss_vector': vector_string,
            'base_score': base_score,
            'severity': severity,
            'metrics': vector,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

    def calculate_all_vulnerabilities(self):
        """모든 정의된 취약점에 대한 CVSS 계산"""
        results = []
        for vuln_type in self.vulnerability_profiles.keys():
            results.append(self.calculate_vulnerability(vuln_type))
        return results

def main():
    parser = argparse.ArgumentParser(description='SMTP/DNS CVSS 3.1 Calculator')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--vuln-type', 
                       choices=['open_relay', 'starttls_downgrade', 'dns_recursion', 
                               'plaintext_auth', 'dane_mta_sts_bypass', 'all'],
                       help='취약점 유형 선택')
    group.add_argument('--vector', 
                       help='CVSS 벡터 문자열 (예: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:L")')
    parser.add_argument('--output', '-o', 
                       help='결과 저장할 JSON 파일 경로')
    parser.add_argument('--format', 
                       choices=['json', 'table'],
                       default='json',
                       help='출력 형식')
    
    args = parser.parse_args()
    
    calculator = CVSSCalculator()
    
    try:
        if args.vector:
            results = [calculator.calculate_from_vector(args.vector)]
        elif args.vuln_type == 'all':
            results = calculator.calculate_all_vulnerabilities()
        else:
            results = [calculator.calculate_vulnerability(args.vuln_type)]
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    if args.format == 'json':
        output = {
            'cvss_analysis': results,
            'generated_at': datetime.now(timezone.utc).isoformat(),
            'tool': 'smtp-dns-vuln-lab CVSS Calculator v1.0'
        }
        
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                json.dump(output, f, indent=2, ensure_ascii=False)
            print(f"CVSS analysis saved to: {args.output}")
        else:
            print(json.dumps(output, indent=2, ensure_ascii=False))
    
    elif args.format == 'table':
        print(f"{'Vulnerability':<25} {'CVSS Score':<12} {'Severity':<10} {'Vector'}")
        print("-" * 80)
        for result in results:
            print(f"{result['vulnerability_type']:<25} "
                  f"{result['base_score']:<12} "
                  f"{result['severity']:<10} "
                  f"{result['cvss_vector']}")

if __name__ == '__main__':
    main()
