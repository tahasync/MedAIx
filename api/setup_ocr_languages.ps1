$ErrorActionPreference = 'Stop'

$tesseract = Join-Path $env:ProgramFiles 'Tesseract-OCR\tesseract.exe'
$systemTessdata = Join-Path $env:ProgramFiles 'Tesseract-OCR\tessdata'
$localTessdata = Join-Path $PSScriptRoot '.tessdata'
$englishModel = Join-Path $systemTessdata 'eng.traineddata'
$urduModel = Join-Path $localTessdata 'urd.traineddata'

if (-not (Test-Path -LiteralPath $tesseract)) {
    throw "Tesseract was not found at $tesseract. Install Tesseract OCR first."
}
if (-not (Test-Path -LiteralPath $englishModel)) {
    throw "English language data was not found at $englishModel."
}

New-Item -ItemType Directory -Force -Path $localTessdata | Out-Null
Copy-Item -LiteralPath $englishModel -Destination (Join-Path $localTessdata 'eng.traineddata') -Force
Invoke-WebRequest `
    -Uri 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/urd.traineddata' `
    -OutFile $urduModel

$env:TESSDATA_PREFIX = $localTessdata
& $tesseract --list-langs
