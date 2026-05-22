param(
    [string]$Script = (Join-Path $PSScriptRoot "PasteMenu.ahk"),
    [int]$TimeoutMs = 1500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AhkExe {
    $candidates = @(
        "C:\Program Files\AutoHotkey\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    throw "AutoHotkey v2 executable not found."
}

function Test-AhkLoad {
    param(
        [Parameter(Mandatory=$true)][string]$AhkExe,
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [int]$TimeoutMs = 1500
    )

    $stdout = Join-Path $env:TEMP ("ahk_smoke_out_" + [guid]::NewGuid().ToString("N") + ".txt")
    $stderr = Join-Path $env:TEMP ("ahk_smoke_err_" + [guid]::NewGuid().ToString("N") + ".txt")

    try {
        $args = "/ErrorStdOut `"$ScriptPath`""
        $p = Start-Process -FilePath $AhkExe -ArgumentList $args -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $exited = $p.WaitForExit($TimeoutMs)
        if (-not $exited) {
            try { Stop-Process -Id $p.Id -Force } catch {}
        }

        $outText = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { "" }
        $errText = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { "" }
        $combined = ($outText + "`n" + $errText).Trim()

        $hasSyntaxMarker = $combined -match "==>"
        return [pscustomobject]@{
            RunningPastTimeout = -not $exited
            Output = $combined
            HasSyntaxError = $hasSyntaxMarker
        }
    }
    finally {
        Remove-Item -Force $stdout, $stderr -ErrorAction SilentlyContinue
    }
}

$ahk = Get-AhkExe
Write-Host "[INFO] Using: `"$ahk`""

Write-Host ""
Write-Host "[STEP] Load/parse check PasteMenu.ahk"
$result = Test-AhkLoad -AhkExe $ahk -ScriptPath $Script -TimeoutMs $TimeoutMs
if ($result.HasSyntaxError) {
    Write-Host "[FAIL] PasteMenu.ahk has load/parse issues." -ForegroundColor Red
    if ($result.Output) { Write-Host $result.Output }
    exit 1
}
Write-Host "[PASS] PasteMenu.ahk check ok."

Write-Host ""
Write-Host "[STEP] Structural presence checks"
$required = @(
    "includes\core_storage.ahk",
    "includes\script_runner.ahk",
    "includes\runtime_hotkeys.ahk",
    "includes\ui_settings.ahk",
    "includes\startup.ahk",
    "includes\core_snippets_backup.ahk",
    "includes\runtime_context_menu.ahk",
    "includes\ui_editor.ahk",
    "includes\paste_markup.ahk"
)
foreach ($rel in $required) {
    $full = Join-Path $PSScriptRoot $rel
    if (-not (Test-Path $full)) {
        Write-Host "[FAIL] Missing include: $rel" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[PASS] All expected include modules exist."

Write-Host ""
Write-Host "[DONE] Automated checks passed."
Write-Host "Next: run manual checks in SMOKE_CHECKLIST.md"
exit 0
