# Pull reference frames from a Keystone Kapers gameplay video.
#
# WHY A SCRIPT AND NOT CHECKED-IN FRAMES: the frames are someone else's video.
# The observations they support live in DESIGN.md 0a; the frames themselves stay
# in a scratch directory and are regenerated on demand. Nothing here goes in git
# except this script.
#
# THREE THINGS ON THIS MACHINE MAKE THE OBVIOUS COMMAND LINE FAIL, and all three
# fail with errors that point somewhere other than the cause:
#
#  1. yt-dlp is a pip install under CYGWIN python 3.9, not an .exe. Invoking it
#     as `yt-dlp` from PowerShell gets "Cannot run a document in the middle of a
#     pipeline" -- it is a shebang script. Call the interpreter with -m instead.
#  2. The default YouTube player client fails with "The page needs to be
#     reloaded" (the installed yt-dlp is ~a year old). player_client=android
#     still works and offers itag 18 (progressive 480x360 mp4), which is plenty:
#     the 2600 is 160x192 native, so 480x360 is already better than 2x.
#  3. The only ffmpeg here is the one bundled with KRITA, and it is built
#     WITHOUT HTTPS support -- "Protocol not found". That kills --download-
#     sections, which streams through ffmpeg. So download the whole progressive
#     file with yt-dlp's own downloader (17 MB) and cut it locally afterwards,
#     where ffmpeg only ever touches a file:// path.
#
# Usage:  .\grabref.ps1 [-VideoId <id>] [-OutDir <path>]

param(
    [string]$VideoId = "TW9JQ8KYlWY",   # "Keystone Kapers - Atari 2600 - 4K 60FPS Gameplay"
    [string]$OutDir  = "$env:TEMP\kkref"
)

$Python = "C:\cygwin64\bin\python3.9.exe"
$Ffmpeg = "C:\Program Files\Krita (x64)\bin\ffmpeg.exe"

foreach ($p in @($Python, $Ffmpeg)) {
    if (-not (Test-Path $p)) { throw "not found: $p" }
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$mp4 = Join-Path $OutDir "kk.mp4"

if (-not (Test-Path $mp4)) {
    Write-Host "downloading $VideoId ..."
    & $Python -m yt_dlp --no-warnings --no-part `
        --extractor-args "youtube:player_client=android" -f 18 `
        -o $mp4 "https://www.youtube.com/watch?v=$VideoId"
    if (-not (Test-Path $mp4)) { throw "download produced no file" }
}

# Contact sheets: one frame every 6 s, 4x3 to a sheet. These are for SURVEYING
# -- finding the timestamp where a thing is on screen -- not for reading detail.
Write-Host "contact sheets ..."
for ($i = 0; $i -lt 4; $i++) {
    $start = 30 + $i * 72
    & $Ffmpeg -y -loglevel error -ss $start -i $mp4 -t 72 `
        -vf "fps=1/6,scale=320:180,tile=4x3" -frames:v 1 `
        (Join-Path $OutDir "sheet$i.png")
}

# Detail crops. Coordinates are in the video's NATIVE 480x360 frame; the store
# occupies roughly x 24..464, y 20..305, with the scanner at y 262..306.
# scale=neighbor is not optional -- bilinear smears 2600 pixels into mush.
$crops = @(
    @{ n = "hud";    t = 120; c = "300:48:90:20";    z = 5 },
    @{ n = "scanner";t = 120; c = "280:44:100:262";  z = 6 },
    @{ n = "elevator";t= 150; c = "180:190:130:105"; z = 5 },
    @{ n = "escalator";t=30;  c = "200:170:110:110"; z = 5 },
    @{ n = "cart";   t = 186; c = "440:230:24:75";   z = 3 },
    @{ n = "biplane";t = 258; c = "200:120:130:100"; z = 7 },
    @{ n = "radio";  t = 282; c = "200:120:130:150"; z = 7 }
)
Write-Host "detail crops ..."
foreach ($k in $crops) {
    & $Ffmpeg -y -loglevel error -ss $k.t -i $mp4 -frames:v 1 `
        -vf "crop=$($k.c),scale=iw*$($k.z):ih*$($k.z):flags=neighbor" `
        (Join-Path $OutDir "z_$($k.n).png")
}

Write-Host "`nframes in $OutDir"
Get-ChildItem $OutDir -Filter *.png | Select-Object Name, Length
