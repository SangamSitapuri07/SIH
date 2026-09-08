# ============================================================
#  ORCA - One-Command Updater (Windows PowerShell 5.1+)
#  "Pull hua ya nahi" confusion ka permanent ilaaj.
#
#  NOTE: Yeh file jan-bhoojh kar 100% plain-ASCII hai.
#  PowerShell 5.1 bina BOM wali UTF-8 file ko galat encoding
#  mein padhta hai (em-dash/emoji = parse error) - isliye is
#  script mein koi special character NAHI hai.
#
#  Kya karta hai:
#    1. Local edits/package-lock conflicts ko STASH karta hai
#       (kuch DELETE nahi hota - 'git stash pop' se waapas aata hai)
#    2. git pull --ff-only (merge-editor kabhi nahi khulega)
#    3. Current commit HASH dikhata hai
#    4. Python deps check/install (venv mein, agar zaroorat ho)
#    5. package.json badla ho toh npm install kar deta hai
#
#  Run:   Right-click -> Run with PowerShell
#     ya: powershell -ExecutionPolicy Bypass -File .\update-orca.ps1
# ============================================================
$ErrorActionPreference = "Stop"

function Say($msg, $color = "White") { Write-Host $msg -ForegroundColor $color }

Say "`n=== ORCA update shuru ===" -Color Cyan
Set-Location $PSScriptRoot

# 0) git repo check
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { throw "Yeh folder git repo nahi lagta: $PSScriptRoot" }

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
Say "Branch: $branch"

# 1) local changes stash (package-lock.json conflicts ka #1 kaaran)
$dirty = git status --porcelain
if ($dirty) {
    Say "`nLocal changes mili (npm install ka package-lock aksar):" -Color Yellow
    $dirty | ForEach-Object { Say "   $_" -Color DarkYellow }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git stash push -u -m "orca-update auto-stash $stamp" | Out-Host
    Say "-> Stash ho gaya (waapas chahiye toh: git stash pop)" -Color Yellow
} else {
    Say "Local changes: koi nahi - clean."
}

# 2) pull (fast-forward only - kabhi merge editor nahi)
Say "`nPull ho raha hai..."
git pull --ff-only
if ($LASTEXITCODE -ne 0) {
    Say "PULL FAIL ho gaya - upar red error padho aur mujhe bhejo." -Color Red
    exit 1
}

# 3) current commit
$commit = (git rev-parse --short HEAD).Trim()
$gitmsg = (git log --oneline -1).Trim()
Say "`nAb tum is commit par ho:" -Color Green
Say "   $gitmsg" -Color Green
Say "Backend restart karte hi header mein 'git:$commit' chip dikhna chahiye." -Color Cyan

# 4) Python deps - venv dhoondo, zaroorat ho toh install
$venvPy = $null
$candidates = @(
    (Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe"),
    (Join-Path $PSScriptRoot ".venv\Scripts\python.exe"),
    (Join-Path $PSScriptRoot "venv\Scripts\python.exe")
)
foreach ($c in $candidates) { if (Test-Path $c) { $venvPy = $c; break } }

if ($venvPy) {
    $reqChanged = git diff --name-only "HEAD@{1}" HEAD -- pipeline/requirements.txt backend/requirements.txt 2>$null
    # fast import-check: koi zaroori package missing toh install (idempotent)
    & $venvPy -c "import fastapi, global_land_mask" 2>$null
    if ($LASTEXITCODE -ne 0 -or $reqChanged) {
        Say "`nPython deps install ho rahe hain (requirements badle ya package missing)..." -Color Yellow
        & $venvPy -m pip install -q -r (Join-Path $PSScriptRoot "pipeline\requirements.txt") -r (Join-Path $PSScriptRoot "backend\requirements.txt")
        if ($LASTEXITCODE -ne 0) {
            Say "PIP INSTALL FAIL - net check karke yeh command khud chalao:" -Color Red
            Say "   & '$venvPy' -m pip install -r pipeline\requirements.txt -r backend\requirements.txt" -Color Red
        } else {
            Say "Python deps: [OK]" -Color Green
        }
    } else {
        Say "Python deps: [OK] (kuch install karne ki zaroorat nahi)"
    }
} else {
    Say "`nWARNING: venv ka python.exe nahi mila - deps manually check karo." -Color Yellow
}

# 5) npm deps (sirf jab package.json/lock badle hon)
$pkgChanged = git diff --name-only "HEAD@{1}" HEAD -- web/package.json web/package-lock.json 2>$null
if ($pkgChanged) {
    Say "`nweb/package.json badla - npm install chala raha hoon..." -Color Yellow
    Push-Location (Join-Path $PSScriptRoot "web")
    npm install --no-audit --no-fund
    Pop-Location
} else {
    Say "`nweb deps: koi change nahi (npm install skip)."
}

Say "`n=== AB YEH KARO ===" -Color Cyan
Say "  1. Backend:  .\start-backend.ps1     (restart ZAROORI hai)"
Say "  2. Frontend: cd web ; npm run dev"
Say "  3. Browser:  Ctrl+Shift+R (hard refresh)"
Say "  4. Header mein check karo: 'git:$commit' dikha toh latest code chal raha hai. [OK]`n"
