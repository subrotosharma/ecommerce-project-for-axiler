#!/usr/bin/env python3
"""
Smoke Tests for E-Commerce Platform
Run after deployment to verify basic functionality
"""

import sys
import time
import json
import argparse
import requests
from typing import Dict, List, Tuple
from datetime import datetime
from urllib.parse import urljoin

class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

class SmokeTests:
    def __init__(self, base_url: str, env: str = 'dev'):
        self.base_url = base_url
        self.env = env
        self.results = []
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'SmokeTest/1.0',
            'Accept': 'application/json'
        })
        
    def log(self, message: str, level: str = 'INFO'):
        """Log messages with color coding"""
        colors = {
            'INFO': Colors.BLUE,
            'SUCCESS': Colors.GREEN,
            'WARNING': Colors.YELLOW,
            'ERROR': Colors.RED
        }
        color = colors.get(level, '')
        print(f"{color}[{level}]{Colors.ENDC} {message}")
    
    def test_endpoint(self, name: str, url: str, method: str = 'GET', 
                      expected_status: int = 200, timeout: int = 10,
                      data: Dict = None) -> Tuple[bool, float]:
        """Test a single endpoint"""
        full_url = urljoin(self.base_url, url)
        start_time = time.time()
        
        try:
            if method == 'GET':
                response = self.session.get(full_url, timeout=timeout)
            elif method == 'POST':
                response = self.session.post(full_url, json=data, timeout=timeout)
            elif method == 'PUT':
                response = self.session.put(full_url, json=data, timeout=timeout)
            elif method == 'DELETE':
                response = self.session.delete(full_url, timeout=timeout)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            response_time = (time.time() - start_time) * 1000  # Convert to ms
            
            if response.status_code == expected_status:
                self.log(f"✓ {name}: {response.status_code} ({response_time:.2f}ms)", 'SUCCESS')
                self.results.append({
                    'test': name,
                    'url': full_url,
                    'status': 'PASS',
                    'response_time': response_time,
                    'status_code': response.status_code
                })
                return True, response_time
            else:
                self.log(f"✗ {name}: Expected {expected_status}, got {response.status_code}", 'ERROR')
                self.results.append({
                    'test': name,
                    'url': full_url,
                    'status': 'FAIL',
                    'response_time': response_time,
                    'status_code': response.status_code,
                    'error': f"Expected {expected_status}, got {response.status_code}"
                })
                return False, response_time
                
        except requests.exceptions.Timeout:
            self.log(f"✗ {name}: Timeout after {timeout}s", 'ERROR')
            self.results.append({
                'test': name,
                'url': full_url,
                'status': 'FAIL',
                'error': 'Timeout'
            })
            return False, timeout * 1000
            
        except Exception as e:
            self.log(f"✗ {name}: {str(e)}", 'ERROR')
            self.results.append({
                'test': name,
                'url': full_url,
                'status': 'FAIL',
                'error': str(e)
            })
            return False, 0
    
    def run_health_checks(self):
        """Run health check tests"""
        self.log("Running Health Checks...", 'INFO')
        
        services = [
            ('Frontend Health', '/health'),
            ('API Gateway Health', '/api/health'),
            ('Product Service Health', '/api/products/health'),
            ('Order Service Health', '/api/orders/health'),
            ('User Service Health', '/api/users/health'),
        ]
        
        for name, endpoint in services:
            self.test_endpoint(name, endpoint)
    
    def run_api_tests(self):
        """Run API functionality tests"""
        self.log("\nRunning API Tests...", 'INFO')
        
        # Test API info endpoint
        self.test_endpoint('API Info', '/api')
        
        # Test product endpoints
        self.test_endpoint('List Products', '/api/products')
        self.test_endpoint('Get Product', '/api/products/1')
        
        # Test user endpoints
        self.test_endpoint('User Registration', '/api/users/register', 
                          method='POST', expected_status=201,
                          data={
                              'username': f'testuser_{int(time.time())}',
                              'email': f'test_{int(time.time())}@example.com',
                              'password': 'TestPass123!'
                          })
        
        # Test order endpoints
        self.test_endpoint('List Orders', '/api/orders', expected_status=200)
    
    def run_performance_tests(self):
        """Run basic performance tests"""
        self.log("\nRunning Performance Tests...", 'INFO')
        
        endpoints = ['/api/products', '/api/users', '/api/orders']
        
        for endpoint in endpoints:
            response_times = []
            for i in range(10):
                success, response_time = self.test_endpoint(
                    f'Performance Test {i+1}', 
                    endpoint
                )
                if success:
                    response_times.append(response_time)
            
            if response_times:
                avg_time = sum(response_times) / len(response_times)
                max_time = max(response_times)
                min_time = min(response_times)
                
                self.log(f"\nPerformance Summary for {endpoint}:", 'INFO')
                self.log(f"  Average: {avg_time:.2f}ms", 'INFO')
                self.log(f"  Min: {min_time:.2f}ms", 'INFO')
                self.log(f"  Max: {max_time:.2f}ms", 'INFO')
                
                if avg_time > 1000:
                    self.log(f"  Warning: Average response time > 1s", 'WARNING')
    
    def run_security_tests(self):
        """Run basic security tests"""
        self.log("\nRunning Security Tests...", 'INFO')
        
        # Test for exposed sensitive endpoints
        sensitive_endpoints = [
            ('Admin without auth', '/admin', 401),
            ('Metrics without auth', '/metrics', 401),
            ('Config endpoint', '/config', 404),
            ('Environment vars', '/env', 404),
            ('.git folder', '/.git/config', 404),
        ]
        
        for name, endpoint, expected_status in sensitive_endpoints:
            self.test_endpoint(name, endpoint, expected_status=expected_status)
        
        # Test for security headers
        response = self.session.get(self.base_url)
        security_headers = {
            'X-Content-Type-Options': 'nosniff',
            'X-Frame-Options': ['DENY', 'SAMEORIGIN'],
            'X-XSS-Protection': '1; mode=block',
            'Strict-Transport-Security': 'max-age='
        }
        
        self.log("\nSecurity Headers Check:", 'INFO')
        for header, expected_value in security_headers.items():
            if header in response.headers:
                if isinstance(expected_value, list):
                    if any(val in response.headers[header] for val in expected_value):
                        self.log(f"  ✓ {header}: {response.headers[header]}", 'SUCCESS')
                    else:
                        self.log(f"  ✗ {header}: Invalid value", 'ERROR')
                elif expected_value in response.headers[header]:
                    self.log(f"  ✓ {header}: {response.headers[header]}", 'SUCCESS')
                else:
                    self.log(f"  ✗ {header}: Invalid value", 'ERROR')
            else:
                self.log(f"  ✗ {header}: Missing", 'WARNING')
    
    def run_monitoring_tests(self):
        """Test monitoring endpoints"""
        self.log("\nRunning Monitoring Tests...", 'INFO')
        
        # Test Prometheus metrics
        self.test_endpoint('Prometheus Metrics', '/metrics', expected_status=200)
        
        # Test readiness and liveness
        self.test_endpoint('Readiness Probe', '/ready')
        self.test_endpoint('Liveness Probe', '/health')
    
    def generate_report(self):
        """Generate test report"""
        total_tests = len(self.results)
        passed_tests = len([r for r in self.results if r['status'] == 'PASS'])
        failed_tests = total_tests - passed_tests
        pass_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        print(f"\n{Colors.BOLD}{'='*60}{Colors.ENDC}")
        print(f"{Colors.BOLD}SMOKE TEST REPORT - {self.env.upper()} ENVIRONMENT{Colors.ENDC}")
        print(f"{Colors.BOLD}{'='*60}{Colors.ENDC}")
        print(f"Timestamp: {datetime.now().isoformat()}")
        print(f"Base URL: {self.base_url}")
        print(f"\nResults:")
        print(f"  Total Tests: {total_tests}")
        print(f"  {Colors.GREEN}Passed: {passed_tests}{Colors.ENDC}")
        print(f"  {Colors.RED}Failed: {failed_tests}{Colors.ENDC}")
        print(f"  Pass Rate: {pass_rate:.1f}%")
        
        if failed_tests > 0:
            print(f"\n{Colors.RED}Failed Tests:{Colors.ENDC}")
            for result in self.results:
                if result['status'] == 'FAIL':
                    print(f"  - {result['test']}: {result.get('error', 'Unknown error')}")
        
        # Save detailed report to file
        report_file = f"smoke_test_report_{self.env}_{int(time.time())}.json"
        with open(report_file, 'w') as f:
            json.dump({
                'environment': self.env,
                'timestamp': datetime.now().isoformat(),
                'base_url': self.base_url,
                'summary': {
                    'total': total_tests,
                    'passed': passed_tests,
                    'failed': failed_tests,
                    'pass_rate': pass_rate
                },
                'results': self.results
            }, f, indent=2)
        
        print(f"\nDetailed report saved to: {report_file}")
        
        return failed_tests == 0
    
    def run_all_tests(self):
        """Run all smoke tests"""
        print(f"{Colors.BOLD}Starting Smoke Tests for {self.env.upper()} environment{Colors.ENDC}")
        print(f"Base URL: {self.base_url}\n")
        
        self.run_health_checks()
        self.run_api_tests()
        self.run_performance_tests()
        self.run_security_tests()
        self.run_monitoring_tests()
        
        return self.generate_report()

def main():
    parser = argparse.ArgumentParser(description='Run smoke tests for the e-commerce platform')
    parser.add_argument('--env', default='dev', choices=['dev', 'staging', 'prod'],
                       help='Environment to test')
    parser.add_argument('--url', help='Base URL to test (overrides environment default)')
    parser.add_argument('--tests', nargs='+', 
                       choices=['health', 'api', 'performance', 'security', 'monitoring', 'all'],
                       default=['all'], help='Tests to run')
    
    args = parser.parse_args()
    
    # Determine base URL
    if args.url:
        base_url = args.url
    else:
        # Get URL from kubectl ingress
        import subprocess
        try:
            result = subprocess.run(
                ['kubectl', 'get', 'ingress', 'frontend', '-o', 
                 'jsonpath={.status.loadBalancer.ingress[0].hostname}'],
                capture_output=True, text=True
            )
            if result.returncode == 0 and result.stdout:
                base_url = f"http://{result.stdout}"
            else:
                base_url = f"http://localhost:{'3000' if args.env == 'dev' else '80'}"
        except:
            base_url = f"http://localhost:{'3000' if args.env == 'dev' else '80'}"
    
    # Run tests
    tester = SmokeTests(base_url, args.env)
    
    if 'all' in args.tests:
        success = tester.run_all_tests()
    else:
        if 'health' in args.tests:
            tester.run_health_checks()
        if 'api' in args.tests:
            tester.run_api_tests()
        if 'performance' in args.tests:
            tester.run_performance_tests()
        if 'security' in args.tests:
            tester.run_security_tests()
        if 'monitoring' in args.tests:
            tester.run_monitoring_tests()
        
        success = tester.generate_report()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()