# Turns Blender's bee pictures (..\blender\out\icon-*.png) into finished menu pictures in ..\ui-icons:
# trimmed, centred, 512 x 512, with the same dark ink outline as the other pictures.
param([double]$Outline = 9, [int]$Size = 512)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$from = Join-Path $root 'blender\out'
$out = Join-Path $root 'ui-icons'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition (Get-Content -Raw (Join-Path $here 'IconRenderer.cs'))

$names = New-Object 'System.Collections.Generic.List[string]'
$pictures = New-Object 'System.Collections.Generic.List[System.Drawing.Bitmap]'
foreach ($file in Get-ChildItem $from -Filter 'icon-*.png' | Sort-Object Name) {
    $name = $file.BaseName.Substring(5)
    $image = [IconRenderer]::FromFile($file.FullName, $Size, 0.86)
    if ($Outline -gt 0) { $image = [IconRenderer]::Outline($image, $Outline, '14101a') }
    $bitmap = [IconRenderer]::ToBitmap($image)
    $bitmap.Save((Join-Path $out ($name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $names.Add($name)
    $pictures.Add($bitmap)
}
[IconRenderer]::Sheet($names, $pictures, (Join-Path $out '_sheet-blender.png'), 5)
"finished $($names.Count) pictures: $($names -join ', ')"
