# Draws every UI picture listed in models.txt into ..\ui-icons\<Name>.png (512 x 512, see-through background).
# Usage:  powershell -File render-icons.ps1 [-Outline 9] [-Size 512]
param(
    [double]$Outline = 9,      # thickness of the dark ink line around each picture (0 = none)
    [int]$Size = 512,
    [string]$Only = ''         # draw just one picture, e.g. -Only Coin
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $here) 'ui-icons'
New-Item -ItemType Directory -Force $out | Out-Null

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition (Get-Content -Raw (Join-Path $here 'IconRenderer.cs'))

$models = [IconRenderer]::Load((Join-Path $here 'models.txt'))
$names = New-Object 'System.Collections.Generic.List[string]'
$pictures = New-Object 'System.Collections.Generic.List[System.Drawing.Bitmap]'
foreach ($model in $models) {
    if ($Only -and $model.Name -ne $Only) { continue }
    $image = [IconRenderer]::Render($model, $Size, 3, 0.86)
    if ($Outline -gt 0) { $image = [IconRenderer]::Outline($image, $Outline, '14101a') }
    $bitmap = [IconRenderer]::ToBitmap($image)
    $bitmap.Save((Join-Path $out ($model.Name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $names.Add($model.Name)
    $pictures.Add($bitmap)
}
[IconRenderer]::Sheet($names, $pictures, (Join-Path $out '_sheet.png'), 5)
"drew $($names.Count) pictures into $out"
