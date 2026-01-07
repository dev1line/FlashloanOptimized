#!/usr/bin/env python3
"""
Audit Automation Script với Auto-fix cho FlashloanOptimized Project
- Chạy Slither và Aderyn audit
- Parse và tổng hợp findings
- Tự động fix một số issues có thể fix được
- Tạo HTML report với UI đẹp
"""

import json
import subprocess
import sys
import re
import os
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, asdict
from enum import Enum
from datetime import datetime

# Color codes for terminal output
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    MAGENTA = '\033[95m'
    CYAN = '\033[96m'
    END = '\033[0m'
    BOLD = '\033[1m'

class IssueSeverity(Enum):
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    INFORMATIONAL = "INFORMATIONAL"
    OPTIMIZATION = "OPTIMIZATION"

@dataclass
class Issue:
    severity: IssueSeverity
    title: str
    description: str
    file: str
    line: Optional[int] = None
    code_snippet: Optional[str] = None
    auto_fixable: bool = False
    fix_suggestion: Optional[str] = None

class AuditAutomation:
    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.issues: List[Issue] = []
        self.fixed_issues: List[Issue] = []
        self.review_needed: List[Issue] = []
        
    def print_header(self, text: str):
        print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*80}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.CYAN}{text.center(80)}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'='*80}{Colors.END}\n")
    
    def print_success(self, text: str):
        print(f"{Colors.GREEN}✓ {text}{Colors.END}")
    
    def print_error(self, text: str):
        print(f"{Colors.RED}✗ {text}{Colors.END}")
    
    def print_warning(self, text: str):
        print(f"{Colors.YELLOW}⚠ {text}{Colors.END}")
    
    def print_info(self, text: str):
        print(f"{Colors.BLUE}ℹ {text}{Colors.END}")
    
    def run_slither(self) -> bool:
        """Chạy Slither audit"""
        self.print_header("Running Slither Audit")
        
        try:
            if os.path.exists('/.dockerenv'):
                cmd = ['slither', '.',
                       '--filter-paths', 'lib,node_modules,cache,out',
                       '--config-file', 'slither.config.json',
                       '--print', 'human-summary',
                       '--json', 'slither-report.json']
            elif os.path.exists(self.project_root / 'docker-compose.yml'):
                cmd = ['docker-compose', 'exec', '-T', 'flashloan-audit', 'slither', '.',
                       '--filter-paths', 'lib,node_modules,cache,out',
                       '--config-file', 'slither.config.json',
                       '--print', 'human-summary',
                       '--json', 'slither-report.json']
            else:
                cmd = ['slither', '.',
                       '--filter-paths', 'lib,node_modules,cache,out',
                       '--config-file', 'slither.config.json',
                       '--print', 'human-summary',
                       '--json', 'slither-report.json']
            
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)
            
            if result.returncode == 0:
                self.print_success("Slither audit completed")
                print(result.stdout)
                return True
            else:
                self.print_warning(f"Slither completed with warnings: {result.stderr[:200]}")
                print(result.stdout)
                return True
                
        except Exception as e:
            self.print_error(f"Failed to run Slither: {e}")
            return False
    
    def run_aderyn(self) -> bool:
        """Chạy Aderyn audit"""
        self.print_header("Running Aderyn Audit")
        
        try:
            if os.path.exists('/.dockerenv'):
                cmd = ['aderyn', '.', '--skip-build']
            elif os.path.exists(self.project_root / 'docker-compose.yml'):
                cmd = ['docker-compose', 'exec', '-T', 'flashloan-audit', 'aderyn', '.', '--skip-build']
            else:
                cmd = ['aderyn', '.', '--skip-build']
            
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)
            
            if os.path.exists(self.project_root / 'report.md'):
                self.print_success("Aderyn audit completed (report.md generated)")
                if result.stderr:
                    self.print_warning("Aderyn had some warnings, but report was generated")
                return True
            else:
                self.print_error(f"Aderyn failed: {result.stderr[:500]}")
                return False
                
        except Exception as e:
            self.print_error(f"Failed to run Aderyn: {e}")
            return False
    
    def parse_aderyn_report(self):
        """Parse Aderyn markdown report"""
        self.print_header("Parsing Aderyn Report")
        
        report_path = self.project_root / 'report.md'
        if not report_path.exists():
            self.print_warning("report.md not found, skipping Aderyn parsing")
            return
        
        content = report_path.read_text()
        
        # Split content into sections
        sections = re.split(r'\n## ([^\n]+)\n', content)
        
        for i in range(1, len(sections), 2):
            if i + 1 >= len(sections):
                break
            
            section_title = sections[i]
            section_content = sections[i + 1]
            
            # Determine severity
            severity = None
            issue_id = None
            title = None
            
            if section_title.startswith('H-'):
                severity = IssueSeverity.HIGH
                match = re.match(r'H-(\d+): (.+)', section_title)
                if match:
                    issue_id = match.group(1)
                    title = match.group(2)
            elif section_title.startswith('L-'):
                severity = IssueSeverity.LOW
                match = re.match(r'L-(\d+): (.+)', section_title)
                if match:
                    issue_id = match.group(1)
                    title = match.group(2)
            
            if not severity or not title:
                continue
            
            # Extract description (first paragraph)
            description = section_content.split('\n\n')[0].strip()
            
            # Extract file and line info
            file_line_pattern = r'- Found in ([^\s]+) \[Line: (\d+)\]'
            for file_match in re.finditer(file_line_pattern, section_content):
                file_path = file_match.group(1)
                line_num = int(file_match.group(2))
                
                # Extract code snippet
                start_pos = file_match.end()
                next_match_pos = section_content.find('- Found in', start_pos)
                if next_match_pos == -1:
                    snippet_section = section_content[start_pos:]
                else:
                    snippet_section = section_content[start_pos:next_match_pos]
                
                code_snippet_match = re.search(r'```solidity\n(.*?)\n```', snippet_section, re.DOTALL)
                code_snippet = code_snippet_match.group(1).strip() if code_snippet_match else None
                
                full_title = f"{severity.value[:1]}-{issue_id}: {title}"
                
                issue = Issue(
                    severity=severity,
                    title=full_title,
                    description=description[:200],
                    file=file_path,
                    line=line_num,
                    code_snippet=code_snippet,
                    auto_fixable=self._is_auto_fixable(title, file_path, line_num),
                    fix_suggestion=self._get_fix_suggestion(title, file_path, line_num)
                )
                self.issues.append(issue)
        
        self.print_success(f"Parsed {len(self.issues)} issues from Aderyn report")
    
    def _is_auto_fixable(self, title: str, file_path: str, line_num: int) -> bool:
        """Check if issue can be auto-fixed"""
        auto_fixable_keywords = [
            "Missing checks for `address(0)`",
            "Define and use `constant`",
            "Large literal values multiples of 10000",
            "Return value of the function call is not checked"
        ]
        
        return any(keyword in title for keyword in auto_fixable_keywords)
    
    def _get_fix_suggestion(self, title: str, file_path: str, line_num: int) -> Optional[str]:
        """Get fix suggestion for issue"""
        if "Missing checks for `address(0)`" in title:
            return "Add require(_addr != address(0), 'Invalid address') check before assignment"
        elif "Define and use `constant`" in title:
            return "Create constant variable BPS_DENOMINATOR = 1e4 and use it instead of 10000"
        elif "Large literal values multiples of 10000" in title:
            return "Replace 10000 with 1e4 (scientific notation) or use BPS_DENOMINATOR constant"
        elif "Return value of the function call is not checked" in title:
            return "Use SafeERC20 library from OpenZeppelin or check return values explicitly"
        elif "Unsafe ERC20 Operations" in title:
            return "Migrate to SafeERC20 library from OpenZeppelin contracts"
        elif "Event is missing `indexed` fields" in title:
            return "Add 'indexed' keyword to event parameters for better off-chain indexing"
        elif "Centralization Risk" in title:
            return "Document owner privileges, consider multi-sig, or implement timelock"
        elif "Solidity pragma should be specific" in title:
            return "Consider using specific version instead of ^ (e.g., 0.8.22 instead of ^0.8.22)"
        
        return "Review and fix manually based on best practices"
    
    def generate_html_report(self):
        """Generate beautiful HTML report with filtering"""
        self.print_header("Generating HTML Report")
        
        # Categorize issues
        for issue in self.issues:
            if issue.auto_fixable and issue not in self.fixed_issues:
                # Will be auto-fixed
                pass
            else:
                self.review_needed.append(issue)
        
        # Statistics
        severity_counts = {}
        auto_fixable_count = sum(1 for i in self.issues if i.auto_fixable)
        by_file = {}
        
        for issue in self.issues:
            severity_counts[issue.severity] = severity_counts.get(issue.severity, 0) + 1
            if issue.file not in by_file:
                by_file[issue.file] = []
            by_file[issue.file].append(issue)
        
        html_content = self._generate_html_template(severity_counts, auto_fixable_count, by_file)
        
        report_path = self.project_root / 'audit-report.html'
        report_path.write_text(html_content)
        
        self.print_success(f"HTML report saved to {report_path}")
        self.print_info(f"Open {report_path} in your browser to view the report")
    
    def _generate_html_template(self, severity_counts, auto_fixable_count, by_file):
        """Generate HTML template with modern UI"""
        
        # Convert issues to JSON for JavaScript
        issues_json = json.dumps([
            {
                'severity': i.severity.value,
                'title': i.title,
                'description': i.description,
                'file': i.file,
                'line': i.line,
                'code_snippet': i.code_snippet,
                'auto_fixable': i.auto_fixable,
                'fix_suggestion': i.fix_suggestion or 'No suggestion available'
            }
            for i in self.issues
        ], indent=2)
        
        return f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audit Report - FlashloanOptimized</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }}
        
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        .header h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
        }}
        
        .header .meta {{
            opacity: 0.9;
            font-size: 1.1em;
        }}
        
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }}
        
        .stat-card {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }}
        
        .stat-card .number {{
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }}
        
        .stat-card.high .number {{ color: #dc3545; }}
        .stat-card.medium .number {{ color: #fd7e14; }}
        .stat-card.low .number {{ color: #ffc107; }}
        .stat-card.auto-fixable .number {{ color: #28a745; }}
        .stat-card.total .number {{ color: #007bff; }}
        
        .filters {{
            padding: 20px 30px;
            background: white;
            border-bottom: 1px solid #e9ecef;
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            align-items: center;
        }}
        
        .filter-group {{
            display: flex;
            gap: 10px;
            align-items: center;
        }}
        
        .filter-group label {{
            font-weight: 600;
            color: #495057;
        }}
        
        .filter-btn {{
            padding: 8px 16px;
            border: 2px solid #dee2e6;
            background: white;
            border-radius: 6px;
            cursor: pointer;
            transition: all 0.3s;
            font-weight: 500;
        }}
        
        .filter-btn:hover {{
            border-color: #667eea;
            color: #667eea;
        }}
        
        .filter-btn.active {{
            background: #667eea;
            color: white;
            border-color: #667eea;
        }}
        
        .search-box {{
            flex: 1;
            min-width: 200px;
            padding: 10px 15px;
            border: 2px solid #dee2e6;
            border-radius: 6px;
            font-size: 1em;
        }}
        
        .search-box:focus {{
            outline: none;
            border-color: #667eea;
        }}
        
        .issues-container {{
            padding: 30px;
        }}
        
        .issue-card {{
            background: white;
            border-left: 4px solid #dee2e6;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            transition: all 0.3s;
        }}
        
        .issue-card:hover {{
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            transform: translateY(-2px);
        }}
        
        .issue-card.high {{ border-left-color: #dc3545; }}
        .issue-card.medium {{ border-left-color: #fd7e14; }}
        .issue-card.low {{ border-left-color: #ffc107; }}
        .issue-card.informational {{ border-left-color: #17a2b8; }}
        
        .issue-header {{
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 15px;
        }}
        
        .issue-title {{
            font-size: 1.3em;
            font-weight: 600;
            color: #212529;
            flex: 1;
        }}
        
        .severity-badge {{
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
            text-transform: uppercase;
            margin-left: 15px;
        }}
        
        .severity-badge.high {{ background: #dc3545; color: white; }}
        .severity-badge.medium {{ background: #fd7e14; color: white; }}
        .severity-badge.low {{ background: #ffc107; color: #212529; }}
        .severity-badge.informational {{ background: #17a2b8; color: white; }}
        
        .auto-fix-badge {{
            background: #28a745;
            color: white;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 0.75em;
            font-weight: 600;
            margin-left: 10px;
        }}
        
        .issue-meta {{
            display: flex;
            gap: 20px;
            margin-bottom: 15px;
            font-size: 0.9em;
            color: #6c757d;
        }}
        
        .issue-meta span {{
            display: flex;
            align-items: center;
            gap: 5px;
        }}
        
        .issue-description {{
            color: #495057;
            line-height: 1.6;
            margin-bottom: 15px;
        }}
        
        .code-snippet {{
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 6px;
            padding: 15px;
            margin: 15px 0;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            overflow-x: auto;
        }}
        
        .fix-suggestion {{
            background: #e7f3ff;
            border-left: 4px solid #007bff;
            padding: 15px;
            border-radius: 6px;
            margin-top: 15px;
        }}
        
        .fix-suggestion h4 {{
            color: #007bff;
            margin-bottom: 8px;
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        
        .fix-suggestion p {{
            color: #495057;
            line-height: 1.6;
        }}
        
        .empty-state {{
            text-align: center;
            padding: 60px 20px;
            color: #6c757d;
        }}
        
        .empty-state svg {{
            width: 100px;
            height: 100px;
            margin-bottom: 20px;
            opacity: 0.5;
        }}
        
        @media (max-width: 768px) {{
            .filters {{
                flex-direction: column;
                align-items: stretch;
            }}
            
            .filter-group {{
                flex-direction: column;
                align-items: stretch;
            }}
            
            .issue-header {{
                flex-direction: column;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Audit Report</h1>
            <div class="meta">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
        </div>
        
        <div class="stats">
            <div class="stat-card total">
                <div class="number">{len(self.issues)}</div>
                <div>Total Issues</div>
            </div>
            <div class="stat-card high">
                <div class="number">{severity_counts.get(IssueSeverity.HIGH, 0)}</div>
                <div>High</div>
            </div>
            <div class="stat-card medium">
                <div class="number">{severity_counts.get(IssueSeverity.MEDIUM, 0)}</div>
                <div>Medium</div>
            </div>
            <div class="stat-card low">
                <div class="number">{severity_counts.get(IssueSeverity.LOW, 0)}</div>
                <div>Low</div>
            </div>
            <div class="stat-card auto-fixable">
                <div class="number">{auto_fixable_count}</div>
                <div>Auto-fixable</div>
            </div>
        </div>
        
        <div class="filters">
            <div class="filter-group">
                <label>Severity:</label>
                <button class="filter-btn active" data-filter="all" onclick="filterIssues('all')">All</button>
                <button class="filter-btn" data-filter="HIGH" onclick="filterIssues('HIGH')">High</button>
                <button class="filter-btn" data-filter="MEDIUM" onclick="filterIssues('MEDIUM')">Medium</button>
                <button class="filter-btn" data-filter="LOW" onclick="filterIssues('LOW')">Low</button>
            </div>
            
            <div class="filter-group">
                <label>Type:</label>
                <button class="filter-btn active" data-filter-type="all" onclick="filterByType('all')">All</button>
                <button class="filter-btn" data-filter-type="auto-fixable" onclick="filterByType('auto-fixable')">Auto-fixable</button>
                <button class="filter-btn" data-filter-type="manual" onclick="filterByType('manual')">Manual</button>
            </div>
            
            <input type="text" class="search-box" placeholder="🔍 Search by file, title, or description..." oninput="searchIssues(this.value)">
        </div>
        
        <div class="issues-container" id="issuesContainer">
            <!-- Issues will be rendered here -->
        </div>
    </div>
    
    <script>
        const issues = {issues_json};
        let filteredIssues = issues;
        let currentSeverityFilter = 'all';
        let currentTypeFilter = 'all';
        
        function renderIssues() {{
            const container = document.getElementById('issuesContainer');
            
            if (filteredIssues.length === 0) {{
                container.innerHTML = `
                    <div class="empty-state">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor">
                            <circle cx="12" cy="12" r="10"></circle>
                            <line x1="12" y1="8" x2="12" y2="12"></line>
                            <line x1="12" y1="16" x2="12.01" y2="16"></line>
                        </svg>
                        <h2>No issues found</h2>
                        <p>Try adjusting your filters</p>
                    </div>
                `;
                return;
            }}
            
            container.innerHTML = filteredIssues.map(issue => {{
                const severityClass = issue.severity.toLowerCase();
                return `
                    <div class="issue-card ${{severityClass}}" data-severity="${{issue.severity}}" data-auto-fixable="${{issue.auto_fixable}}">
                        <div class="issue-header">
                            <div class="issue-title">
                                ${{issue.title}}
                                ${{issue.auto_fixable ? '<span class="auto-fix-badge">Auto-fixable</span>' : ''}}
                            </div>
                            <span class="severity-badge ${{severityClass}}">${{issue.severity}}</span>
                        </div>
                        <div class="issue-meta">
                            <span>📁 <strong>File:</strong> ${{issue.file}}</span>
                            ${{issue.line ? `<span>📍 <strong>Line:</strong> ${{issue.line}}</span>` : ''}}
                        </div>
                        <div class="issue-description">${{issue.description}}</div>
                        ${{issue.code_snippet ? `
                            <div class="code-snippet">
                                <pre><code>${{escapeHtml(issue.code_snippet)}}</code></pre>
                            </div>
                        ` : ''}}
                        ${{issue.fix_suggestion ? `
                            <div class="fix-suggestion">
                                <h4>💡 Fix Suggestion</h4>
                                <p>${{issue.fix_suggestion}}</p>
                            </div>
                        ` : ''}}
                    </div>
                `;
            }}).join('');
        }}
        
        function escapeHtml(text) {{
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }}
        
        function filterIssues(severity) {{
            currentSeverityFilter = severity;
            document.querySelectorAll('[data-filter]').forEach(btn => {{
                btn.classList.toggle('active', btn.dataset.filter === severity);
            }});
            applyFilters();
        }}
        
        function filterByType(type) {{
            currentTypeFilter = type;
            document.querySelectorAll('[data-filter-type]').forEach(btn => {{
                btn.classList.toggle('active', btn.dataset.filterType === type);
            }});
            applyFilters();
        }}
        
        function searchIssues(query) {{
            const searchTerm = query.toLowerCase();
            applyFilters(searchTerm);
        }}
        
        function applyFilters(searchTerm = '') {{
            filteredIssues = issues.filter(issue => {{
                // Severity filter
                if (currentSeverityFilter !== 'all' && issue.severity !== currentSeverityFilter) {{
                    return false;
                }}
                
                // Type filter
                if (currentTypeFilter === 'auto-fixable' && !issue.auto_fixable) {{
                    return false;
                }}
                if (currentTypeFilter === 'manual' && issue.auto_fixable) {{
                    return false;
                }}
                
                // Search filter
                if (searchTerm) {{
                    const searchable = `${{issue.title}} ${{issue.description}} ${{issue.file}}`.toLowerCase();
                    if (!searchable.includes(searchTerm)) {{
                        return false;
                    }}
                }}
                
                return true;
            }});
            
            renderIssues();
        }}
        
        // Initial render
        renderIssues();
    </script>
</body>
</html>'''
    
    def auto_fix_issues(self):
        """Tự động fix các issues có thể fix được"""
        self.print_header("Auto-fixing Issues")
        # Auto-fix logic would go here
        # For now, just categorize
        pass
    
    def run_full_audit(self):
        """Run complete audit workflow"""
        self.print_header("Starting Full Audit Workflow")
        
        # Step 1: Run audits
        slither_ok = self.run_slither()
        aderyn_ok = self.run_aderyn()
        
        if not slither_ok and not aderyn_ok:
            self.print_error("Both audits failed!")
            return False
        
        # Step 2: Parse reports
        self.parse_aderyn_report()
        
        # Step 3: Generate HTML report
        self.generate_html_report()
        
        self.print_header("Audit Workflow Complete")
        self.print_success(f"Total issues found: {len(self.issues)}")
        self.print_success(f"HTML report generated: audit-report.html")
        
        return True

def main():
    project_root = Path(__file__).parent.parent
    automation = AuditAutomation(project_root)
    
    if len(sys.argv) > 1:
        if sys.argv[1] == '--report-only':
            automation.parse_aderyn_report()
            automation.generate_html_report()
        else:
            print("Usage: audit-autofix.py [--report-only]")
            sys.exit(1)
    else:
        automation.run_full_audit()

if __name__ == '__main__':
    main()
