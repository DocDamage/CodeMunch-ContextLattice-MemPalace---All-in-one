# PowerShell Unicode Safety Guide for AI Agents

## Related Docs
- [Technical Debt Audit Summary](../implementation/TECHNICAL_DEBT_AUDIT.md)
- [Implementation Progress](../implementation/PROGRESS.md)
- [Remaining Work](../implementation/REMAINING_WORK.md)
- [Troubleshooting Guide](../operations/TROUBLESHOOTING.md)

## Quick Summary for Agent Code Generation

**ALWAYS use ASCII-only characters in generated PowerShell code.** Unicode symbols cause parse errors on Windows due to encoding mismatches.

---

## 1. Why Unicode Characters Fail in PowerShell on Windows

### Root Cause: The "BOM Problem"

PowerShell 5.1 (Windows PowerShell) defaults to **Windows-1252** encoding when reading files without a Byte Order Mark (BOM). When Unicode characters (like ✓, ✗, ⚠) are written without proper UTF-8 BOM, they become corrupted "mojibake" (e.g., `�"?�"?`).

```powershell
# BAD: This will cause "Unexpected token" errors when imported
$summary = "✓ Summary: Task completed"
$divider = "─────────────────────────"
```

**Error Example:**
```
Unexpected token '�"?�"? Summary �"?�"?...'
At line:1 char:12
+ $summary = �"?�"? Summary
+            ~~~~~~~~~~~~~~
```

### Encoding Chain of Failure

1. Agent generates file with UTF-8 (no BOM) containing Unicode
2. `Add-Content` or `Set-Content` writes to disk
3. PowerShell 5.1 reads file → interprets as Windows-1252
4. Multi-byte UTF-8 characters → multiple garbage characters
5. Parser encounters invalid tokens → cryptic error

---

## 2. ASCII-Safe Symbol Alternatives

| **DO NOT USE** | **USE INSTEAD** | **Example Output** |
|----------------|-----------------|-------------------|
| ✓ (U+2713) | `[OK]` or `OK` | `[OK] Task completed` |
| ✗ (U+2717) | `[FAIL]` or `FAIL` | `[FAIL] Connection failed` |
| ⚠ (U+26A0) | `[WARN]` or `WARN` | `[WARN] Deprecated API` |
| ─ (U+2500) | `-` or `=` | `----------` or `==========` |
| ┌ ┐ └ ┘ (box drawing) | `+` and `-` | `+---------+` |
| → (U+2192) | `->` or `=>` | `Step 1 -> Step 2` |
| ✎ (U+270E) | `[EDIT]` | `[EDIT] Configuration` |
| ℹ (U+2139) | `[INFO]` | `[INFO] Processing...` |
| ✖ (U+2716) | `[X]` | `[X] Invalid input` |

### Recommended Patterns from This Codebase

```powershell
# GOOD: From doctor-llm-workflow.ps1
$status = if ($check.Ok) { "OK" } else { "FAIL" }
Write-Output ("[{0}] {1}: {2}" -f $status, $check.Name, $check.Detail)

# Output: [OK] python_command: C:\Python311\python.exe
# Output: [FAIL] provider_credentials: No provider key found
```

---

## 3. Safe Characters for PowerShell String Literals

### Always Safe (ASCII 32-126)
```
Space through tilde:   !"#$%&'()*+,-./0123456789:;<=>?
                       @ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_
                       `abcdefghijklmnopqrstuvwxyz{|}~
```

### Use with Caution (requires escaping)
| Character | Escaping Required | Context |
|-----------|-------------------|---------|
| `$` | `` `$ `` | Double-quoted strings |
| `"` | `""` or `\"` | Double-quoted strings |
| `'` | `''` | Single-quoted strings |
| `` ` `` | ``` `` ``` | Escape character itself |
| `
` | `` `n `` | Line breaks (double-quoted) |
| `	` | `` `t `` | Tabs (double-quoted) |

---

## 4. Escaping in PowerShell Strings

### Single-Quoted Strings (`'...'`)
- **No variable expansion**
- **No escape sequences** (except `''` for literal single quote)
- Safest for file paths and literal text

```powershell
# GOOD: Literal strings
$path = 'C:\Users\Doc\Projects\file.txt'
$message = 'It''s working!'  # '' = literal '
```

### Double-Quoted Strings (`"..."`)
- **Variable expansion**: `$var` and `$($expression)`
- **Escape sequences**: `` `n ``, `` `t ``, `` `" ``, etc.
- Requires escaping `$` with `` `$ ``

```powershell
# Variable expansion
$name = "World"
$greeting = "Hello, $name!"        # Hello, World!

# Expression expansion
$sum = "2 + 2 = $($num1 + $num2)"  # 2 + 2 = 4

# Escaping special characters
$price = "The cost is `$50"        # The cost is $50
$quote = "She said `"Hello`"""     # She said "Hello"
```

### Here-Strings (`@"..."@`)
- Multi-line strings
- **Same escaping rules as double-quoted strings**
- Closing marker `@"` or `@'` must be at start of line

```powershell
# Double-quoted here-string (expands variables)
$template = @"
[STATUS] Deployment Report
==========================
Status: $status
Host:   $env:COMPUTERNAME
"@

# Single-quoted here-string (NO expansion - SAFER for templates)
$literal = @'
[STATUS] Deployment Report
==========================
Status: $status      # Literal $status, not a variable
Host:   $env:COMPUTERNAME  # Literal text
'@
```

### Escape Sequence Reference
| Sequence | Meaning | Example |
|----------|---------|---------|
| `` `0 `` | Null | `$nullChar = "`0"` |
| `` `a `` | Alert (beep) | ``Write-Host "`aDone!"`` |
| `` `b `` | Backspace | ``"abc`b`" → "ab"`` |
| `` `f `` | Form feed | Legacy printers |
| `` `n `` | New line | ``"Line1`nLine2"`` |
| `` `r `` | Carriage return | ``"Line1`rLine2"`` (overwrites) |
| `` `t `` | Tab | ``"Col1`tCol2"`` |
| `` `v `` | Vertical tab | Rarely used |

---

## 5. Avoiding Backslash-Escaping Issues with Add-Content

### The Problem

When using `Add-Content` or `Set-Content` to write PowerShell variables containing backslashes, the content may be double-escaped or interpreted incorrectly.

```powershell
# BAD: Double-escaping disaster
$content = '{ "path": "C:\\Users\\Doc" }'
Add-Content -Path "file.json" -Value $content
# Result: C:\\Users\\Doc (doubled backslashes!)

# BAD: Unicode corruption
$summary = "✓ Summary: Task completed"
Set-Content -Path "script.ps1" -Value $summary
# Result: �"?�"? Summary (encoding corruption)
```

### Safe Patterns

#### Pattern 1: Use Single-Quoted Strings for Paths
```powershell
# GOOD: Single quotes prevent backslash interpretation
$path = 'C:\Users\Doc\Projects\myfile.txt'
Add-Content -Path "output.txt" -Value $path
```

#### Pattern 2: Use Here-Strings for Complex Content
```powershell
# GOOD: Here-strings preserve content exactly
$scriptContent = @'
$ErrorActionPreference = "Stop"
$logPath = 'C:\Logs\application.log'

function Write-Log {
    param([string]$Message)
    "[$(Get-Date)] $Message" | Out-File -FilePath $logPath -Append
}
'@

Set-Content -Path "generated-script.ps1" -Value $scriptContent -Encoding UTF8
```

#### Pattern 3: Always Specify Encoding
```powershell
# GOOD: Explicit encoding prevents corruption
Set-Content -Path "script.ps1" -Value $content -Encoding UTF8
Add-Content -Path "log.txt" -Value $entry -Encoding UTF8

# BEST: UTF8 with BOM for PowerShell 5.1 compatibility
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText("script.ps1", $content, $utf8Bom)
```

#### Pattern 4: Use New-Item with -Value
```powershell
# GOOD: Atomic write operation
New-Item -Path "script.ps1" -ItemType File -Value $content -Force
```

#### Pattern 5: Using Out-File with Explicit Encoding
```powershell
# GOOD: Out-File with UTF8 encoding
$jsonContent = '{ "path": "C:\Users\Doc" }'
$jsonContent | Out-File -FilePath "config.json" -Encoding UTF8
```

---

## 6. Agent Checklist for PowerShell Code Generation

Before generating PowerShell code, verify:

- [ ] **NO Unicode symbols**: Replace ✓, ✗, ⚠, ─ with `[OK]`, `[FAIL]`, `[WARN]`, `-`
- [ ] **NO emoji**: Avoid all emoji characters (even in comments)
- [ ] **ASCII-only output**: Stick to characters 32-126
- [ ] **Proper string quoting**:
  - File paths → Single quotes (`'C:\path'`)
  - User messages with variables → Double quotes
  - Templates → Single-quoted here-strings (`@'...'@`)
- [ ] **Specify encoding**: Always use `-Encoding UTF8` with file commands
- [ ] **Escape special chars**: `` `$ ``, `` `" ``, `` `n `` in double quotes
- [ ] **Test before final**: Verify generated script loads without parse errors

---

## 7. Quick Reference Card

```powershell
# ═══════════════════════════════════════════════════
# SAFE SYMBOL REPLACEMENTS
# ═══════════════════════════════════════════════════
# ✓  → [OK]    ✗ → [FAIL]   ⚠ → [WARN]
# ─  → -       → → ->       │ → |
# ┌┐└┘ → +-

# ═══════════════════════════════════════════════════
# STRING BEST PRACTICES
# ═══════════════════════════════════════════════════

# File paths (no expansion needed)
$path = 'C:\Users\Name\file.txt'

# User messages (with variables)
$msg = "Processing file: $filename"

# Multi-line templates (no expansion - safest)
$template = @'
function Get-Status {
    return "[OK] Operation completed"
}
'@

# File writing (always specify encoding)
Set-Content -Path "file.ps1" -Value $content -Encoding UTF8

# ═══════════════════════════════════════════════════
# ESCAPING CHEAT SHEET
# ═══════════════════════════════════════════════════
# In double quotes:    `$  = literal $
#                      `"  = literal "
#                      `n  = newline
# In single quotes:    ''  = literal '
# In here-strings:     Same as parent quote type
```

---

## 8. Testing Generated PowerShell

Always verify generated code can be parsed:

```powershell
# Test parse without execution
$scriptPath = "generated-script.ps1"
$errors = $null
[void][System.Management.Automation.PSParser]::Tokenize(
    (Get-Content $scriptPath -Raw), 
    [ref]$errors
)
if ($errors.Count -gt 0) {
    Write-Error "Parse errors found in generated script!"
    $errors | ForEach-Object { Write-Error $_.Message }
}
```

