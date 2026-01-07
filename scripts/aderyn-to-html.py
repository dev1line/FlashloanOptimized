#!/usr/bin/env python3
"""
Script to convert Aderyn markdown report to HTML and display console summary
Similar to Slither's human-summary output
"""

import sys
import re
from pathlib import Path
from typing import List, Dict, Tuple
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

def print_header(text: str):
    print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*80}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.CYAN}{text.center(80)}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.CYAN}{'='*80}{Colors.END}\n")

def print_section(text: str):
    print(f"\n{Colors.BOLD}{Colors.BLUE}{text}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'-'*len(text)}{Colors.END}")

def parse_aderyn_markdown(md_path: Path) -> Dict:
    """Parse Aderyn markdown report"""
    if not md_path.exists():
        return {}
    
    content = md_path.read_text()
    
    # Extract summary
    summary = {}
    # Try to find Files Summary table
    files_summary_match = re.search(r'## Files Summary(.*?)(?=## |$)', content, re.DOTALL)
    if files_summary_match:
        table_section = files_summary_match.group(1)
        # Look for table rows
        for line in table_section.split('\n'):
            if '|' in line and line.strip() and not line.strip().startswith('|---'):
                parts = [p.strip() for p in line.split('|') if p.strip()]
                if len(parts) >= 2:
                    summary[parts[0]] = parts[1]
    
    # Also try to extract from the summary section directly
    summary_section = re.search(r'## Summary(.*?)(?=## |$)', content, re.DOTALL)
    if summary_section:
        for line in summary_section.group(1).split('\n'):
            if '|' in line and line.strip() and not line.strip().startswith('|---'):
                parts = [p.strip() for p in line.split('|') if p.strip()]
                if len(parts) >= 2:
                    summary[parts[0]] = parts[1]
    
    # Extract issues by severity
    issues = {
        'high': [],
        'medium': [],
        'low': [],
        'informational': []
    }
    
    # Find High Issues section
    high_section = re.search(r'# High Issues(.*?)(?=# |$)', content, re.DOTALL)
    if high_section:
        high_issues = re.findall(r'### (H-\d+): (.*?)(?=### |$)', high_section.group(1), re.DOTALL)
        for issue_id, issue_content in high_issues:
            issues['high'].append({
                'id': issue_id,
                'title': issue_content.split('\n')[0].strip(),
                'content': issue_content.strip()
            })
    
    # Find Medium Issues section
    medium_section = re.search(r'# Medium Issues(.*?)(?=# |$)', content, re.DOTALL)
    if medium_section:
        medium_issues = re.findall(r'### (M-\d+): (.*?)(?=### |$)', medium_section.group(1), re.DOTALL)
        for issue_id, issue_content in medium_issues:
            issues['medium'].append({
                'id': issue_id,
                'title': issue_content.split('\n')[0].strip(),
                'content': issue_content.strip()
            })
    
    # Find Low Issues section
    low_section = re.search(r'# Low Issues(.*?)(?=# |$)', content, re.DOTALL)
    if low_section:
        low_issues = re.findall(r'### (L-\d+): (.*?)(?=### |$)', low_section.group(1), re.DOTALL)
        for issue_id, issue_content in low_issues:
            issues['low'].append({
                'id': issue_id,
                'title': issue_content.split('\n')[0].strip(),
                'content': issue_content.strip()
            })
    
    return {
        'summary': summary,
        'issues': issues
    }

def display_console_summary(data: Dict):
    """Display console summary similar to Slither's human-summary"""
    print_header("Aderyn Security Analysis Summary")
    
    # Display summary statistics
    if 'summary' in data and data['summary']:
        print_section("Summary Statistics")
        for key, value in data['summary'].items():
            print(f"  {Colors.BOLD}{key}:{Colors.END} {value}")
    
    # Display issues by severity
    total_issues = 0
    for severity in ['high', 'medium', 'low']:
        count = len(data.get('issues', {}).get(severity, []))
        total_issues += count
        if count > 0:
            color = Colors.RED if severity == 'high' else Colors.YELLOW if severity == 'medium' else Colors.BLUE
            print(f"\n{color}{Colors.BOLD}{severity.upper()} Issues: {count}{Colors.END}")
            for issue in data['issues'][severity][:5]:  # Show first 5
                print(f"  {Colors.BOLD}{issue['id']}:{Colors.END} {issue['title']}")
            if count > 5:
                print(f"  {Colors.BLUE}... and {count - 5} more{Colors.END}")
    
    print(f"\n{Colors.BOLD}Total Issues Found: {total_issues}{Colors.END}")
    print(f"\n{Colors.GREEN}✓ Analysis completed. Check report.md and aderyn-report.html for details.{Colors.END}\n")

def markdown_to_html(md_path: Path, html_path: Path):
    """Convert markdown to HTML with styling"""
    if not md_path.exists():
        return False
    
    md_content = md_path.read_text()
    
    # Basic markdown to HTML conversion
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Aderyn Security Analysis Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        .header h1 {{
            margin: 0;
            font-size: 2em;
        }}
        .header p {{
            margin: 10px 0 0 0;
            opacity: 0.9;
        }}
        .content {{
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #667eea;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }}
        h2 {{
            color: #764ba2;
            margin-top: 30px;
        }}
        h3 {{
            color: #555;
            margin-top: 20px;
        }}
        code {{
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{
            background: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            border-left: 4px solid #667eea;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }}
        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}
        th {{
            background: #667eea;
            color: white;
            font-weight: bold;
        }}
        tr:hover {{
            background: #f9f9f9;
        }}
        .severity-high {{
            color: #dc3545;
            font-weight: bold;
        }}
        .severity-medium {{
            color: #ffc107;
            font-weight: bold;
        }}
        .severity-low {{
            color: #17a2b8;
        }}
        .footer {{
            text-align: center;
            margin-top: 40px;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Aderyn Security Analysis Report</h1>
        <p>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    </div>
    <div class="content">
"""
    
    # Convert markdown to HTML (basic conversion)
    # Headers
    html_content = re.sub(r'^# (.+)$', r'<h1>\1</h1>', md_content, flags=re.MULTILINE)
    html_content = re.sub(r'^## (.+)$', r'<h2>\1</h2>', html_content, flags=re.MULTILINE)
    html_content = re.sub(r'^### (.+)$', r'<h3>\1</h3>', html_content, flags=re.MULTILINE)
    
    # Bold
    html_content = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', html_content)
    
    # Code blocks
    html_content = re.sub(r'```(\w+)?\n(.*?)```', r'<pre><code>\2</code></pre>', html_content, flags=re.DOTALL)
    
    # Inline code
    html_content = re.sub(r'`([^`]+)`', r'<code>\1</code>', html_content)
    
    # Tables
    lines = html_content.split('\n')
    in_table = False
    table_html = []
    result_lines = []
    
    for line in lines:
        if '|' in line and line.strip().startswith('|'):
            if not in_table:
                in_table = True
                table_html = ['<table>']
            table_html.append(line)
        else:
            if in_table:
                # Convert table to HTML
                table_lines = [l for l in table_html if l.strip()]
                if len(table_lines) > 1:
                    result_lines.append(table_lines[0])  # <table>
                    # Header row
                    if len(table_lines) > 2:
                        header_cells = [c.strip() for c in table_lines[1].split('|') if c.strip()]
                        result_lines.append('<thead><tr>')
                        for cell in header_cells:
                            result_lines.append(f'<th>{cell}</th>')
                        result_lines.append('</tr></thead>')
                        result_lines.append('<tbody>')
                        # Data rows
                        for row_line in table_lines[2:]:
                            if '---' not in row_line:
                                cells = [c.strip() for c in row_line.split('|') if c.strip()]
                                result_lines.append('<tr>')
                                for cell in cells:
                                    result_lines.append(f'<td>{cell}</td>')
                                result_lines.append('</tr>')
                        result_lines.append('</tbody>')
                    result_lines.append('</table>')
                in_table = False
                table_html = []
            result_lines.append(line)
    
    html_content = '\n'.join(result_lines)
    
    # Paragraphs
    html_content = re.sub(r'\n\n+', '</p><p>', html_content)
    html_content = '<p>' + html_content + '</p>'
    
    html += html_content
    
    html += """
    </div>
    <div class="footer">
        <p>Generated by Aderyn - Static Analysis Tool for Solidity</p>
        <p>For more information, visit <a href="https://github.com/Cyfrin/aderyn">Aderyn GitHub</a></p>
    </div>
</body>
</html>
"""
    
    html_path.write_text(html)
    return True

def main():
    project_root = Path.cwd()
    md_path = project_root / 'report.md'
    html_path = project_root / 'aderyn-report.html'
    
    if not md_path.exists():
        print(f"{Colors.RED}Error: report.md not found. Please run Aderyn first.{Colors.END}")
        sys.exit(1)
    
    # Parse and display console summary
    data = parse_aderyn_markdown(md_path)
    display_console_summary(data)
    
    # Convert to HTML
    if markdown_to_html(md_path, html_path):
        print(f"{Colors.GREEN}✓ HTML report generated: {html_path}{Colors.END}")
    else:
        print(f"{Colors.RED}✗ Failed to generate HTML report{Colors.END}")
        sys.exit(1)

if __name__ == '__main__':
    main()

