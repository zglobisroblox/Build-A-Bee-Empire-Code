# Pulls every script out of a Roblox place saved as XML (.rbxlx) into a folder of code files,
# laid out like the place's Explorer (the same layout the Rojo tool uses):
#   Script -> Name.server.luau   LocalScript -> Name.client.luau   ModuleScript -> Name.luau
#   a script that has scripts inside it -> a folder Name\ with init.server.luau / init.client.luau / init.luau
# Folders called Backup_* or Imported* (copies kept inside the place) are left out: git keeps the history instead.
#
# Use:  .\export-scripts.ps1 -Place "C:\...\MyGame.rbxlx" -Out "C:\...\MyGame code\src"
# Save the place as XML first: in Studio, open a local copy and use File > Save As, type "Roblox XML Place Files".
param(
    [Parameter(Mandatory = $true)][string]$Place,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Services = @('ServerScriptService', 'ReplicatedStorage', 'ReplicatedFirst', 'StarterPlayer', 'StarterGui', 'ServerStorage'),
    [string[]]$Skip = @('Backup_*', 'Imported*')
)

$scriptClasses = @{ 'Script' = '.server.luau'; 'LocalScript' = '.client.luau'; 'ModuleScript' = '.luau' }

$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load($Place)

function Get-Name($item) {
    $node = $item.SelectSingleNode('Properties/string[@name="Name"]')
    if ($node) { return $node.InnerText }
    return $item.GetAttribute('class')
}

function Get-SafeName([string]$name) {
    $bad = [System.IO.Path]::GetInvalidFileNameChars()
    $chars = $name.ToCharArray() | ForEach-Object { if ($bad -contains $_) { '_' } else { $_ } }
    return (-join $chars).Trim()
}

function Test-Skip([string]$name) {
    foreach ($pattern in $Skip) { if ($name -like $pattern) { return $true } }
    return $false
}

# does this item hold any script (itself or anything inside it)?
function Test-HasScript($item) {
    if ($scriptClasses.ContainsKey($item.GetAttribute('class'))) { return $true }
    return ($item.SelectNodes('.//Item[@class="Script" or @class="LocalScript" or @class="ModuleScript"]').Count -gt 0)
}

$script:count = 0
function Export-Item($item, [string]$folder) {
    $name = Get-Name $item
    if (Test-Skip $name) { return }
    if (-not (Test-HasScript $item)) { return }
    $class = $item.GetAttribute('class')
    $safe = Get-SafeName $name
    $children = @($item.SelectNodes('Item') | Where-Object { Test-HasScript $_ })
    if ($scriptClasses.ContainsKey($class)) {
        $source = $item.SelectSingleNode('Properties/ProtectedString[@name="Source"]')
        $text = if ($source) { $source.InnerText } else { '' }
        if ($children.Count -gt 0) {
            $dir = Join-Path $folder $safe
            New-Item -ItemType Directory -Force $dir | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir ('init' + $scriptClasses[$class])), $text, (New-Object System.Text.UTF8Encoding $false))
            $script:count++
            foreach ($child in $children) { Export-Item $child $dir }
        } else {
            $file = Join-Path $folder ($safe + $scriptClasses[$class])
            $n = 2
            while (Test-Path $file) { $file = Join-Path $folder ($safe + "_$n" + $scriptClasses[$class]); $n++ }
            [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
            $script:count++
        }
    } else {
        $dir = Join-Path $folder $safe
        New-Item -ItemType Directory -Force $dir | Out-Null
        foreach ($child in $children) { Export-Item $child $dir }
    }
}

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
foreach ($service in $Services) {
    $item = $xml.SelectSingleNode("/roblox/Item[@class='$service']")
    if ($item) { Export-Item $item $Out }
}
"exported $($script:count) scripts into $Out"
