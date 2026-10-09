param(
    [ValidateSet('TI','Coleco','All')][string]$Target='TI',
    [switch]$BuildOnly,
    [switch]$TestsOnly
)
$ErrorActionPreference='Stop'
if ($BuildOnly -and $TestsOnly) { throw 'Choose BuildOnly or TestsOnly.' }
Push-Location $PSScriptRoot
$previous=$env:CHOP_TESTS_DONE
try {
    $targets=if ($Target -eq 'All') { @('ti','coleco') } else { @($Target.ToLower()) }
    # Put all requested ROMs on disk before the slower regression suite.
    if (-not $TestsOnly) {
        $env:CHOP_TESTS_DONE='1'
        foreach ($item in $targets) {
            & C:\cygwin64\bin\bash.exe "build-$item.sh"
            if ($LASTEXITCODE -ne 0) { throw "Choplifter $item build failed" }
        }
    }
    if (-not $BuildOnly) {
        & C:\cygwin64\bin\bash.exe -c '/usr/bin/python3 -B tools/check.py'
        if ($LASTEXITCODE -ne 0) { throw 'Choplifter regression suite failed' }
    }
} finally { $env:CHOP_TESTS_DONE=$previous; Pop-Location }
