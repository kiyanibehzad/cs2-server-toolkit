param(
    [Parameter(Mandatory=$true)][string]$Cs2,
    [switch]$InstallLocal
)

$ErrorActionPreference = 'Stop'
$hud = $PSScriptRoot
$compiler = Join-Path $Cs2 'game\bin\win64\resourcecompiler.exe'
if (-not (Test-Path $compiler)) {
    throw 'CS2 Workshop Tools are missing. Enable them in CS2 Settings, then restart Steam.'
}

$addon = 'cs2_toolkit_admin_v2'
$name = 'cs2_toolkit_admin_v2'
$layoutSource = Join-Path $Cs2 "content\csgo_addons\$addon\panorama\layout\custom_game\$name.xml"
$styleSource = Join-Path $Cs2 "content\csgo_addons\$addon\panorama\styles\custom_game\$name.css"
New-Item -ItemType Directory -Force -Path @((Split-Path $layoutSource), (Split-Path $styleSource)) | Out-Null
Copy-Item (Join-Path $hud "layout\$name.xml") $layoutSource -Force
Copy-Item (Join-Path $hud "styles\$name.css") $styleSource -Force

& $compiler -i $layoutSource -r
if ($LASTEXITCODE -ne 0) { throw 'Layout compilation failed.' }
& $compiler -i $styleSource -r
if ($LASTEXITCODE -ne 0) { throw 'Stylesheet compilation failed.' }

$layoutBuilt = Join-Path $Cs2 "game\csgo_addons\$addon\panorama\layout\custom_game\$name.vxml_c"
$styleBuilt = Join-Path $Cs2 "game\csgo_addons\$addon\panorama\styles\custom_game\$name.vcss_c"
foreach ($file in @($layoutBuilt, $styleBuilt)) {
    if (-not (Test-Path $file)) { throw "Missing compiled resource: $file" }
    Write-Output "Built: $file"
}

if ($InstallLocal) {
    $localLayout = Join-Path $Cs2 "game\csgo\panorama\layout\custom_game\$name.vxml_c"
    $localStyle = Join-Path $Cs2 "game\csgo\panorama\styles\custom_game\$name.vcss_c"
    New-Item -ItemType Directory -Force -Path @((Split-Path $localLayout), (Split-Path $localStyle)) | Out-Null
    Copy-Item $layoutBuilt $localLayout -Force
    Copy-Item $styleBuilt $localStyle -Force
    Write-Output 'Local test resources installed. Restart CS2 before testing.'
}
