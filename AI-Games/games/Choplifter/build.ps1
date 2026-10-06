param([ValidateSet('TI','Coleco','All')][string]$Target='TI')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
$previous=$env:CHOP_TESTS_DONE
try {
    $targets=if ($Target -eq 'All') { @('ti','coleco') } else { @($Target.ToLower()) }
    # Run the target-independent tests once per invocation.
    $env:CHOP_TESTS_DONE='0'
    foreach ($item in $targets) {
        & C:\cygwin64\bin\bash.exe "build-$item.sh"
        if ($LASTEXITCODE -ne 0) { throw "Choplifter $item build failed" }
        $env:CHOP_TESTS_DONE='1'
    }
} finally { $env:CHOP_TESTS_DONE=$previous; Pop-Location }
