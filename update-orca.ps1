# ============================================================
#  ORCA — One-Command Updater (Windows PowerShell 5.1+)
#  "Pull hua ya nahi" confusion ka permanent ilaaj.
#
#  Kya karta hai:
#    1. Local edits/package-lock conflicts ko STASH karta hai
#       (kuch DELETE nahi hota — 'git stash pop' se waapas aa
#       jaata hai)
#    2. git pull --ff-only (merge-editor kabhi nahi khulega)
#    3. Current commit HASH dikhata hai
#    4. package.json badla ho toh npm install kar deta hai
#    (Header ka ⎇ chip backend khud git se padhta hai — restart pe)
#
#  Run:   Right-click → Run with PowerShell
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
    Say "Local changes: koi nahi — clean."
}

# 2) pull (fast-forward only — kabhi merge editor nahi)
Say "`nPull ho raha hai..."
git pull --ff-only
if ($LASTEXITCODE -ne 0) {
    Say "PULL FAIL ho gaya — upar red error padho aur mujhe bhejo." -Color Red
    exit 1
}

# 3) current commit
$commit = (git rev-parse --short HEAD).Trim()
$msg = (git log --oneline -1).Trim()
Say "`nAb tum is commit par ho:" -Color Green
Say "   $msg" -Color Green

# 4) build stamp reminder — backend startup pe khud 'git rev-parse'
#    padhta hai, aur UI header ke '⎇' chip mein dikhata hai. Har
#    screenshot ab khud batati hai kaunsa code chal raha hai.
Say "Backend restart karte hi header mein '⎇ $commit' dikhna chahiye." -Color Cyan

# 5) npm deps (sirf jab package.json/lock badle hon)
$pkgChanged = git diff --name-only "HEAD@{1}" HEAD -- web/package.json web/package-lock.json 2>$null
if ($pkgChanged) {
    Say "`nweb/package.json badla — npm install chala raha hoon..." -Color Yellow
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
Say "  4. Header mein check karo: '⎇ $commit' dikha toh latest code chal raha hai. ✅`n"
