<#
.SYNOPSIS
  Builds a Claude Code token-optimization stack on Windows.

.DESCRIPTION
  Installs/configures:
    - Headroom (+ bundled RTK): API-layer compression, wrapped around `claude`
    - codebase-memory-mcp (CBM): knowledge-graph code discovery
    - context-mode + caveman: Claude Code plugins (output sandboxing, terse output)
    - enforcement hooks: block raw cat/head/tail/grep-equivalents in Bash,
      nudge the first Grep/Glob/Read/Search of a session toward CBM
    - settings.json / CLAUDE.md: merged in place via the same Python logic
      used on the CachyOS side, never overwritten wholesale

  IMPORTANT: the enforcement hooks are bash scripts. Claude Code invokes
  hook "command" entries through a shell, so they only work if bash.exe is
  on PATH (Git for Windows ships one, or use WSL). If bash isn't found,
  this script installs everything else and skips only the hook wiring and
  statusline, with a clear warning.

  Review this script before running it — it installs a third-party binary
  (CBM) and two third-party Claude Code plugins via their own install paths.
  Sources are printed at the end.

.NOTES
  Error handling: every step that can fail for a reason that isn't "the
  script itself is broken" (network hiccup, plugin already installed, no
  bash.exe, corrupt existing settings.json, one file locked) is wrapped in
  try/catch, logged as a warning, and the script keeps going. Only missing
  core tools (git, curl, Python) are fatal — nothing past that point works
  without them.

  Idempotent: safe to re-run. Existing settings.json / CLAUDE.md content is
  preserved; a timestamped .bak is written whenever a file actually changes.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Warnings = @()

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  + $msg" -ForegroundColor Green }
function Write-Warn2($msg) {
    Write-Host "  ! $msg" -ForegroundColor Yellow
    $script:Warnings += $msg
}

function Get-Cmd($name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source } else { return $null }
}

$ClaudeDir = Join-Path $HOME ".claude"
$HooksDir  = Join-Path $ClaudeDir "hooks"
try {
    New-Item -ItemType Directory -Force -Path $HooksDir -ErrorAction Stop | Out-Null
} catch {
    Write-Error "Could not create $HooksDir : $($_.Exception.Message). Fatal — nothing else can be written."
    exit 1
}

# ── 0. Preflight — the only fatal-if-missing tools ────────────────────────
Write-Step "Checking required tools"

$missing = @()
foreach ($cmd in @("git", "curl")) {
    if (-not (Get-Cmd $cmd)) { $missing += $cmd }
}
if ($missing.Count -gt 0) {
    Write-Error "Missing (fatal, can't proceed): $($missing -join ', '). Install via winget/choco/scoop and re-run."
    exit 1
}
Write-Ok "git, curl present"

$PythonCmd = $null
foreach ($cand in @("python", "py")) {
    if (Get-Cmd $cand) { $PythonCmd = $cand; break }
}
if (-not $PythonCmd) {
    Write-Error "Python 3.10+ not found (fatal — Headroom and the config merge both need it). Install from python.org or: winget install Python.Python.3, then re-run."
    exit 1
}
Write-Ok "Python found: $PythonCmd"

$HaveClaudeCli = [bool](Get-Cmd "claude")
if ($HaveClaudeCli) {
    Write-Ok "Claude Code CLI found"
} else {
    Write-Warn2 "'claude' CLI not found — plugin installs (context-mode, caveman) will be skipped."
}

$BashPath = Get-Cmd "bash"
if ($BashPath) {
    Write-Ok "bash.exe found: $BashPath (Git for Windows or WSL) — hooks will be wired"
} else {
    Write-Warn2 "No bash.exe on PATH — hook enforcement and statusline will be SKIPPED. Install Git for Windows or use WSL, then re-run."
}

# ── 1. Headroom (+ bundled RTK) ────────────────────────────────────────────
Write-Step "Checking Headroom"
if (Get-Cmd "headroom") {
    Write-Ok "Headroom already installed"
} else {
    Write-Warn2 "Headroom not found — installing"
    try {
        & $PythonCmd -m pip install --user "headroom-ai[all]" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Headroom installed"
        } else {
            Write-Warn2 "Headroom install exited with code $LASTEXITCODE — continuing without it. Retry manually: $PythonCmd -m pip install --user `"headroom-ai[all]`""
        }
    } catch {
        Write-Warn2 "Headroom install failed: $($_.Exception.Message) — continuing without it."
    }
}

if (Get-Cmd "rtk") {
    Write-Ok "RTK found"
} else {
    Write-Warn2 "RTK not found on PATH. It ships bundled inside Headroom, so this is likely fine."
}

# Wire the wrapper into the PowerShell profile so `claude` routes through
# Headroom. Non-fatal if $PROFILE can't be created/written.
Write-Step "Checking Headroom wrapper in PowerShell profile"
try {
    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType File -Force -Path $PROFILE -ErrorAction Stop | Out-Null
    }
    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent -match "headroom wrap claude") {
        Write-Ok "Headroom wrapper already present in `$PROFILE"
    } else {
        Add-Content -Path $PROFILE -Value "`n# Headroom wraps Claude Code for API-layer token compression`nfunction claude { & headroom wrap claude @args }`n" -ErrorAction Stop
        Write-Ok "Added Headroom wrapper to `$PROFILE (restart PowerShell to apply)"
    }
} catch {
    Write-Warn2 "Could not update `$PROFILE ($($_.Exception.Message)) — add manually: function claude { & headroom wrap claude @args }"
}

# ── 2. codebase-memory-mcp (CBM) ──────────────────────────────────────────
Write-Step "Installing codebase-memory-mcp"
$CbmOk = $false
if (Get-Cmd "codebase-memory-mcp") {
    Write-Ok "codebase-memory-mcp already installed"
    $CbmOk = $true
} else {
    try {
        $installerPath = Join-Path $env:TEMP "cbm-install.ps1"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1" -OutFile $installerPath -ErrorAction Stop
        Write-Warn2 "Downloaded installer to $installerPath — inspect it before trusting it (notepad $installerPath)"
        try {
            & $installerPath
            if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                Write-Ok "codebase-memory-mcp installed"
                $CbmOk = $true
            } else {
                Write-Warn2 "CBM installer exited with code $LASTEXITCODE — skipping CBM. Run manually: $installerPath"
            }
        } catch {
            Write-Warn2 "CBM installer failed: $($_.Exception.Message) — skipping CBM. Run manually: $installerPath"
        }
    } catch {
        Write-Warn2 "Could not download CBM installer ($($_.Exception.Message)) — skipping CBM. Retry later from https://github.com/DeusData/codebase-memory-mcp"
    }
}
$localBin = Join-Path $HOME ".local\bin"
if (Test-Path $localBin) {
    $env:Path = "$localBin;$env:Path"
}

# CBM's own installer wires a *non-blocking* Claude Code hook named
# cbm-code-discovery-gate. We deliberately overwrite it in step 4 with a
# stricter, blocking version — CBM install happens first, our hooks second.

# ── 3. Claude Code plugins: context-mode + caveman ────────────────────────
Write-Step "Installing context-mode + caveman plugins"
if ($HaveClaudeCli) {
    function Invoke-ClaudePluginStep($desc, $scriptBlock) {
        try {
            & $scriptBlock *>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Warn2 "$desc failed or already done (exit $LASTEXITCODE)"
            }
        } catch {
            Write-Warn2 "$desc failed: $($_.Exception.Message)"
        }
    }
    Invoke-ClaudePluginStep "context-mode marketplace add" { claude plugin marketplace add mksglu/context-mode }
    Invoke-ClaudePluginStep "context-mode install"          { claude plugin install context-mode@context-mode }
    Invoke-ClaudePluginStep "caveman marketplace add"       { claude plugin marketplace add JuliusBrussee/caveman }
    Invoke-ClaudePluginStep "caveman install"                { claude plugin install caveman@caveman }
    Write-Ok "plugin install commands run (see warnings above for anything skipped)"
} else {
    Write-Warn2 "Skipped plugin install — no 'claude' CLI on PATH"
}

# ── 4. Enforcement hooks (only if bash.exe is available) ──────────────────
if ($BashPath) {
    Write-Step "Writing enforcement hooks to $HooksDir"

    $banRawTools = @'
#!/bin/bash
# PreToolUse Bash gate: block cat/head/tail/find/grep/rg/wc invocations.
set -uo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" = "Bash" ] || exit 0

UNLOCK=/tmp/bash-raw-unlock
check_unlock() {
  local f=$1
  [ -f "$f" ] || return 1
  local mtime
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  local age=$(( $(date +%s) - mtime ))
  if [ "$age" -ge 0 ] && [ "$age" -lt 600 ]; then return 0; fi
  rm -f "$f"; return 1
}
check_unlock "$UNLOCK" && exit 0
check_unlock "/tmp/bash-raw-unlock-$PPID" && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
TRIMMED=$(echo "$CMD" | sed -E 's/^[[:space:]]*//')
FIRST=$(echo "$TRIMMED" | awk '{print $1}')

banned=0
case "$FIRST" in
  cat|head|tail|find|grep|rg|wc) banned=1 ;;
  rtk) exit 0 ;;
esac

if echo "$CMD" | grep -qE '\|\s*(tail|head)\b' && echo "$FIRST" | grep -qE '^(cat|grep|rg|find)$'; then
  echo "BLOCKED: '| tail'/'| head' pipeline truncates but doesn't reduce tokens read. Use context-mode's ctx_batch_execute/ctx_execute instead, or drop the pipe for short (<20 line) output. Override: touch $UNLOCK" >&2
  exit 2
fi

[ "$banned" -eq 0 ] && exit 0

case "$FIRST" in
  cat|head|tail) echo "BLOCKED Bash '$FIRST'. Use the Read tool. Override: touch $UNLOCK." >&2 ;;
  find)          echo "BLOCKED Bash 'find'. Use the Glob tool. Override: touch $UNLOCK." >&2 ;;
  grep|rg)       echo "BLOCKED Bash '$FIRST'. Use the Grep tool. Override: touch $UNLOCK." >&2 ;;
  wc)            echo "BLOCKED Bash 'wc'. Read the file or pipe via rtk. Override: touch $UNLOCK." >&2 ;;
esac
exit 2
'@

    $cbmGate = @'
#!/bin/bash
# Blocks the FIRST Grep/Glob/Read/Search per session, nudging toward CBM.
GATE=/tmp/cbm-code-discovery-gate-$PPID
MARKER=/tmp/cbm-mcp-used-$PPID
if [ -f "$MARKER" ] || [ -f "$GATE" ]; then
    exit 0
fi
touch "$GATE"
echo 'BLOCKED: For code discovery, use codebase-memory-mcp tools first: search_graph(name_pattern) to find functions/classes, trace_path() for call chains, get_code_snippet(qualified_name) to read source. If unindexed, call index_repository first. Fall back to Grep/Glob/Read only for text content search. Retry now.' >&2
exit 2
'@

    $cbmMarker = @'
#!/bin/bash
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL" == mcp__codebase-memory-mcp__* ]]; then
  touch /tmp/cbm-mcp-used-$PPID
fi
exit 0
'@

    $cbmReminder = @'
#!/bin/bash
cat << 'REMINDER'
CRITICAL - Code Discovery Protocol:
1. ALWAYS use codebase-memory-mcp tools FIRST for ANY code exploration:
   - search_graph(name_pattern/label) to find functions/classes/routes
   - trace_path(function_name, mode) for call chains
   - get_code_snippet(qualified_name) to read source (NOT Read/cat)
   - get_architecture(aspects) for project structure
2. Fall back to Grep/Glob/Read ONLY for text content, config, non-code files.
3. If the project is not indexed yet, run index_repository FIRST.
REMINDER
'@

    # Write with LF line endings (bash chokes on CRLF in some contexts).
    # Each write is individually try/caught so one failure doesn't stop the
    # other three, and doesn't take down the rest of the script.
    function Write-UnixFile($Path, $Content) {
        try {
            $normalized = $Content -replace "`r`n", "`n"
            [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
            return $true
        } catch {
            Write-Warn2 "Could not write $Path : $($_.Exception.Message)"
            return $false
        }
    }

    $hooksOk = $true
    $hooksOk = (Write-UnixFile (Join-Path $HooksDir "bash-ban-raw-tools")      $banRawTools) -and $hooksOk
    $hooksOk = (Write-UnixFile (Join-Path $HooksDir "cbm-code-discovery-gate") $cbmGate)      -and $hooksOk
    $hooksOk = (Write-UnixFile (Join-Path $HooksDir "cbm-mcp-marker")         $cbmMarker)     -and $hooksOk
    $hooksOk = (Write-UnixFile (Join-Path $HooksDir "cbm-session-reminder")   $cbmReminder)   -and $hooksOk

    if ($hooksOk) {
        Write-Ok "4 hook scripts written (LF line endings, for bash)"
    } else {
        Write-Warn2 "One or more hook scripts failed to write — enforcement may be incomplete. Check permissions on $HooksDir"
    }
} else {
    Write-Step "Skipping enforcement hooks (no bash.exe on PATH)"
}

# ── 5. Statusline (only if bash available and none already customized) ───
$StatuslinePath = Join-Path $ClaudeDir "statusline-command.sh"
if ($BashPath -and -not (Test-Path $StatuslinePath)) {
    Write-Step "Installing statusline"
    $statusline = @'
#!/usr/bin/env bash
input=$(cat)
RESET='\033[0m'; BOLD='\033[1m'
WHITE='\033[97m'; CYAN='\033[96m'; GREEN='\033[92m'; YELLOW='\033[93m'
ORANGE='\033[38;5;208m'; RED='\033[91m'; BLUE='\033[94m'; MAGENTA='\033[95m'; GRAY='\033[90m'
SEP="${GRAY} | ${RESET}"
user=$(whoami)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_full="${dir//$HOME/~}"
dir_short=$(echo "$dir_full" | awk -F'/' '{n=NF; if(n<=3){print $0}else{print "…/" $(n-1) "/" $n}}')
raw_model=$(echo "$input" | jq -r '.model.display_name // ""')
model=""
if [ -n "$raw_model" ]; then
  prefix=$(echo "$raw_model" | grep -ioE 'Haiku|Sonnet|Opus' | head -1 | cut -c1 | tr '[:upper:]' '[:lower:]')
  version=$(echo "$raw_model" | grep -oE '[0-9]+\.[0-9]+' | tail -1)
  [ -n "$prefix" ] && [ -n "$version" ] && model="${prefix}${version}"
  [ -z "$model" ] && model="$raw_model"
fi
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
make_bar() { local pct=$1 width=${2:-10}; local filled; filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100)*$2+0.5}'); local empty=$((width-filled)); local bar=""; for ((i=0;i<filled;i++)); do bar+="#"; done; for ((i=0;i<empty;i++)); do bar+="."; done; printf '%s' "$bar"; }
pct_color() { local pct=$1; if (( $(echo "$pct < 50" | bc -l) )); then printf '%s' "$GREEN"; elif (( $(echo "$pct < 75" | bc -l) )); then printf '%s' "$YELLOW"; elif (( $(echo "$pct < 90" | bc -l) )); then printf '%s' "$ORANGE"; else printf '%s' "$RED"; fi; }
out="${BOLD}${CYAN}${user}${RESET}${GRAY} in ${RESET}${WHITE}${dir_short}${RESET}"
[ -n "$model" ] && out+="${SEP}${BLUE}${model}${RESET}"
if [ -n "$used_pct" ]; then pct_int=$(printf '%.0f' "$used_pct"); col=$(pct_color "$used_pct"); bar=$(make_bar "$pct_int" 4); out+="${SEP}${GRAY}ctx ${col}${bar} ${pct_int}%${RESET}"; fi
if [ -n "$five_pct" ]; then pct_int=$(printf '%.0f' "$five_pct"); col=$(pct_color "$five_pct"); bar=$(make_bar "$pct_int" 4); out+="${SEP}${GRAY}5h ${col}${bar} ${pct_int}%${RESET}"; fi
if [ -n "$week_pct" ]; then pct_int=$(printf '%.0f' "$week_pct"); col=$(pct_color "$week_pct"); bar=$(make_bar "$pct_int" 4); out+="${SEP}${GRAY}7d ${col}${bar} ${pct_int}%${RESET}"; fi
printf '%b' "$out"
'@
    try {
        $normalized = $statusline -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($StatuslinePath, $normalized, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "statusline-command.sh installed"
    } catch {
        Write-Warn2 "Failed to write $StatuslinePath : $($_.Exception.Message) — skipping statusline"
    }
} elseif (Test-Path $StatuslinePath) {
    Write-Warn2 "statusline-command.sh already exists — leaving it alone"
}

# ── 6. Merge settings.json + CLAUDE.md via Python (same logic as CachyOS) ─
Write-Step "Merging settings.json and CLAUDE.md"

$includeHooks = if ($BashPath) { "True" } else { "False" }
$includeStatusline = if (Test-Path $StatuslinePath) { "True" } else { "False" }

$pyScript = @"
import json, os, re, time

home = os.path.expanduser("~")
claude_dir = os.path.join(home, ".claude")
os.makedirs(claude_dir, exist_ok=True)
include_hooks = $includeHooks
include_statusline = $includeStatusline

def load_json_safely(path):
    """Read+parse JSON, tolerating a corrupt file instead of crashing.
    On parse failure, the corrupt file is preserved under a
    .corrupt.<timestamp> suffix and we proceed as if it didn't exist."""
    if not os.path.exists(path):
        return {}, ""
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    if not raw.strip():
        return {}, raw
    try:
        return json.loads(raw), raw
    except json.JSONDecodeError as e:
        corrupt_backup = path + "." + "corrupt." + time.strftime("%Y%m%dT%H%M%S")
        with open(corrupt_backup, "w", encoding="utf-8") as f:
            f.write(raw)
        print("  ! existing " + os.path.basename(path) + " is not valid JSON (" + str(e) + "); saved as " + corrupt_backup + " and starting fresh")
        return {}, ""

settings_path = os.path.join(claude_dir, "settings.json")
data, raw = load_json_safely(settings_path)

data.setdefault("hooks", {})

def basename_of(cmd):
    if not cmd:
        return ""
    return cmd.strip().split()[-1].split("/")[-1]

def set_hook(event, matcher, command):
    entries = data["hooks"].setdefault(event, [])
    target = basename_of(command)
    for block in entries:
        block["hooks"] = [h for h in block.get("hooks", [])
                           if basename_of(h.get("command", "")) != target]
    entries[:] = [b for b in entries if b.get("hooks")]
    block = next((b for b in entries if b.get("matcher") == matcher), None)
    if block is None:
        block = {"hooks": []}
        if matcher is not None:
            block["matcher"] = matcher
        entries.append(block)
    block["hooks"].append({"type": "command", "command": command})

if include_hooks:
    set_hook("PreToolUse", "Bash", "bash ~/.claude/hooks/bash-ban-raw-tools")
    set_hook("PreToolUse", "Grep|Glob|Read|Search", "bash ~/.claude/hooks/cbm-code-discovery-gate")
    set_hook("PostToolUse", None, "bash ~/.claude/hooks/cbm-mcp-marker")
    set_hook("SessionStart", None, "bash ~/.claude/hooks/cbm-session-reminder")

if include_statusline:
    data.setdefault("statusLine", {"type": "command", "command": "bash ~/.claude/statusline-command.sh"})

plugins = data.setdefault("enabledPlugins", {})
plugins["context-mode@context-mode"] = True
plugins["caveman@caveman"] = True

markets = data.setdefault("extraKnownMarketplaces", {})
markets["context-mode"] = {"source": {"source": "github", "repo": "mksglu/context-mode"}}
markets["caveman"] = {"source": {"source": "github", "repo": "JuliusBrussee/caveman"}}

env = data.setdefault("env", {})
env.setdefault("BASH_MAX_OUTPUT_LENGTH", "10000")
env.setdefault("MAX_MCP_OUTPUT_TOKENS", "10000")

new_raw = json.dumps(data, indent=2) + "\n"
if new_raw != raw:
    if raw:
        backup = settings_path + "." + "bak." + time.strftime("%Y%m%dT%H%M%S")
        with open(backup, "w", encoding="utf-8") as f:
            f.write(raw)
        print("  + backed up previous settings.json -> " + backup)
    with open(settings_path, "w", encoding="utf-8") as f:
        f.write(new_raw)
    print("  + settings.json updated: " + settings_path)
else:
    print("  + settings.json already up to date")

claude_md = os.path.join(claude_dir, "CLAUDE.md")
start = "<!-- token-stack:start -->"
end = "<!-- token-stack:end -->"
block = start + """
## Token-optimization stack
- Code discovery: use codebase-memory-mcp tools first (search_graph, trace_path, get_code_snippet, get_architecture). Fall back to Grep/Glob/Read only for text search, non-code files, or before the project is indexed (run index_repository first).
- Shell: raw cat/head/tail/find/grep/rg in Bash are blocked by a hook where available - use the Read/Glob/Grep tools, or rtk-wrapped commands.
- Large command output (logs, test runs): prefer context-mode's sandboxed execution over pipe-to-head/tail.
- Mermaid diagrams over prose for architecture explanations.
""" + end

content = ""
if os.path.exists(claude_md):
    with open(claude_md, encoding="utf-8") as f:
        content = f.read()

if start in content and end in content:
    new_content = re.sub(re.escape(start) + r".*?" + re.escape(end), block, content, flags=re.S)
else:
    new_content = block + ("\n\n" + content if content.strip() else "\n")

if new_content != content:
    if content:
        backup = claude_md + "." + "bak." + time.strftime("%Y%m%dT%H%M%S")
        with open(backup, "w", encoding="utf-8") as f:
            f.write(content)
        print("  + backed up previous CLAUDE.md -> " + backup)
    with open(claude_md, "w", encoding="utf-8") as f:
        f.write(new_content)
    print("  + CLAUDE.md updated: " + claude_md)
else:
    print("  + CLAUDE.md already up to date")
"@

try {
    $mergeOutput = $pyScript | & $PythonCmd - 2>&1
    $mergeOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "settings.json / CLAUDE.md merge exited with code $LASTEXITCODE — everything else installed above is unaffected. Re-run this script to retry just the merge."
    } else {
        Write-Ok "settings.json / CLAUDE.md merge complete"
    }
} catch {
    Write-Warn2 "settings.json / CLAUDE.md merge failed: $($_.Exception.Message) — everything else installed above is unaffected."
}

# ── Done ────────────────────────────────────────────────────────────────
Write-Step "Install complete"
$cbmLine = if ($CbmOk) { "codebase-memory-mcp (code discovery)" } else { "codebase-memory-mcp — NOT installed, see warnings" }
$hooksLine = if ($BashPath) { "written to $HooksDir" } else { "SKIPPED (no bash.exe)" }
Write-Host @"
Installed / configured:
  - Headroom + RTK (checked/installed, wrapper wired into `$PROFILE)
  - $cbmLine
  - context-mode + caveman Claude Code plugins
  - enforcement hooks: $hooksLine
  - ~/.claude/settings.json  (merged, backup written if changed)
  - ~/.claude/CLAUDE.md      (merged, backup written if changed)

Next steps:
  1. Restart your terminal
  2. cd into a project and run 'claude' - on first code question it will
     prompt to index the repo (or run: codebase-memory-mcp cli index_repository)
  3. Run '/caveman' inside a session to activate terse output mode
$(if (-not $BashPath) { "  4. Install Git for Windows, then re-run this script to enable the enforcement hooks + statusline" })

Sources (read before trusting a downloaded install script):
  CBM:          https://github.com/DeusData/codebase-memory-mcp
  context-mode: https://github.com/mksglu/context-mode
  caveman:      https://github.com/JuliusBrussee/caveman
  hook design adapted from: https://github.com/sgaabdu4/claude-code-tips
"@

if ($Warnings.Count -gt 0) {
    Write-Host "`nCompleted with $($Warnings.Count) non-fatal warning(s):" -ForegroundColor Yellow
    foreach ($w in $Warnings) {
        Write-Host "  - $w" -ForegroundColor Yellow
    }
}
