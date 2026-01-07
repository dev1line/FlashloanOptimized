# Audit Automation Script

Script tự động chạy audit (Slither + Aderyn), parse findings, và tự động fix một số issues có thể fix được.

## Cách sử dụng

### 1. Chạy Full Audit Workflow (khuyến nghị)

```bash
# Trong Docker
make docker-audit-full

# Hoặc local
make audit-full
```

Workflow này sẽ:
1. Chạy Slither audit
2. Chạy Aderyn audit
3. Parse các findings
4. Tự động fix các issues có thể fix
5. Tạo summary report (`audit-summary.md`)

### 2. Chạy chỉ phần auto-fix (sau khi đã có reports)

```bash
# Trong Docker
make docker-audit-autofix

# Hoặc local
make audit-autofix
```

### 3. Chạy trực tiếp script

```bash
# Full audit
python3 scripts/audit-autofix.py

# Chỉ fix (không chạy audits)
python3 scripts/audit-autofix.py --fix-only

# Chỉ generate report
python3 scripts/audit-autofix.py --report-only
```

## Issues được auto-fix

Script tự động fix các issues sau:

1. **L-4: Missing address(0) checks**
   - Thêm `require(_addr != address(0), 'Invalid address')` trước các assignment

2. **L-5 & L-10: Constant variables và scientific notation**
   - Tạo `BPS_DENOMINATOR = 1e4` constant
   - Replace `10000` với `BPS_DENOMINATOR` hoặc `1e4`

3. **H-1: Return value not checked** (partial)
   - Tạo fix suggestions để sử dụng SafeERC20

## Issues cần review thủ công

Các issues sau cần review và fix thủ công:

1. **H-1: Return value not checked**
   - Sử dụng SafeERC20 library
   - Hoặc check return values explicitly

2. **L-1: Centralization Risk**
   - Document owner privileges
   - Consider multi-sig

3. **L-2: Unsafe ERC20 Operations**
   - Migrate to SafeERC20

4. **L-3: Pragma version**
   - Fix nếu cần (hiện tại dùng `^0.8.22`)

5. **L-6: Event indexing**
   - Thêm `indexed` keyword cho event fields

6. **L-7: PUSH0 opcode**
   - Informational - check EVM version compatibility

7. **L-8, L-9, L-11: Code quality**
   - Refactor modifiers, remove empty blocks, clean unused errors

## Output Files

- `slither-report.json` - Slither JSON report
- `report.md` - Aderyn markdown report
- `audit-summary.md` - Tổng hợp findings và fixes (tự động tạo)

## Lưu ý

- Script sẽ tự động detect nếu đang chạy trong Docker
- Các fixes được apply trực tiếp vào source files
- Luôn review `audit-summary.md` trước khi commit
- Backup code trước khi chạy auto-fix

