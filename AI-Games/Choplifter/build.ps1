param([ValidateSet('TI','Coleco','All')][string]$Target='TI')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $targets=if ($Target -eq 'All') { @('ti','coleco') } else { @($Target.ToLower()) }
    foreach ($item in $targets) {
        & C:\cygwin64\bin\bash.exe "build-$item.sh"
        if ($LASTEXITCODE -ne 0) { throw "Choplifter $item build failed" }
    }
} finally { Pop-Location }
