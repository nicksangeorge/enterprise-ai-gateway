<#
.SYNOPSIS
    Runs AI Gateway v2 test suite sequentially with pass/fail reporting.

.PARAMETER SkipFailover
    Skip test5_failover.py (it scales down a Foundry deployment).

.EXAMPLE
    .\run_tests.ps1
    .\run_tests.ps1 -SkipFailover
#>
param(
    [switch]$SkipFailover
)

$ErrorActionPreference = "Continue"

$tests = @(
    @{ Name = "test1_connectivity"; File = "..\tests\test1_connectivity.py"; Desc = "Basic connectivity" },
    @{ Name = "test2_model_router"; File = "..\tests\test2_model_router.py"; Desc = "Model Router" },
    @{ Name = "test3_load";         File = "..\tests\test3_load.py";         Desc = "Concurrent load" },
    @{ Name = "test4_quota";        File = "..\tests\test4_quota.py";        Desc = "Quota enforcement" },
    @{ Name = "test5_failover";     File = "..\tests\test5_failover.py";     Desc = "Circuit breaker failover" },
    @{ Name = "test6_metrics";      File = "..\tests\test6_metrics.py";      Desc = "App Insights metrics" },
    @{ Name = "test7_llm_logs";     File = "..\tests\test7_llm_logs.py";     Desc = "LLM log generation" }
)

$passed  = 0
$failed  = 0
$skipped = 0
$results = @()

Write-Host "`n===== AI Gateway v2 Test Suite =====" -ForegroundColor Cyan
Write-Host ""

foreach ($test in $tests) {
    if ($SkipFailover -and $test.Name -eq "test5_failover") {
        Write-Host "SKIP  $($test.Name) - $($test.Desc)" -ForegroundColor Yellow
        $skipped++
        $results += @{ Name = $test.Name; Status = "SKIP" }
        continue
    }

    Write-Host "RUN   $($test.Name) - $($test.Desc)" -ForegroundColor Cyan -NoNewline
    Write-Host ""

    $exitCode = 0
    try {
        $env:PYTHONUNBUFFERED = "1"
        $testPath = Join-Path $PSScriptRoot $test.File
        & python $testPath 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = 1
        Write-Host "      ERROR: $_" -ForegroundColor Red
    }

    if ($exitCode -eq 0) {
        Write-Host "PASS  $($test.Name)" -ForegroundColor Green
        $passed++
        $results += @{ Name = $test.Name; Status = "PASS" }
    } else {
        Write-Host "FAIL  $($test.Name)" -ForegroundColor Red
        $failed++
        $results += @{ Name = $test.Name; Status = "FAIL" }
    }
    Write-Host ""
}

Write-Host "===== Summary =====" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "SKIP" { "Yellow" }
    }
    Write-Host "  $($r.Status)  $($r.Name)" -ForegroundColor $color
}
Write-Host ""
Write-Host "Passed: $passed  Failed: $failed  Skipped: $skipped" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failed -gt 0) { exit 1 }
