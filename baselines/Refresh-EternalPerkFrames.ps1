param([string]$KronosPath = (Join-Path $PSScriptRoot 'kronos'))
$ErrorActionPreference = 'Stop'
$KronosPath = [IO.Path]::GetFullPath($KronosPath)
$imageRoot = Join-Path $KronosPath 'Assets/Images'
$root = Join-Path $imageRoot 'eternal_perk_frame'
New-Item -ItemType Directory -Path $root -Force | Out-Null
Add-Type -AssemblyName System.Drawing
function Quote-Lua([string]$Value) { return '"' + $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n') + '"' }
$registryFile = Join-Path $root 'pack_ids.json'
$registry = @{}
if (Test-Path -LiteralPath $registryFile) { $old=Get-Content -LiteralPath $registryFile -Raw | ConvertFrom-Json; foreach($p in $old.PSObject.Properties) {$registry[$p.Name]=[int]$p.Value} }
$next = 1
foreach($value in $registry.Values) { if($value -ge $next) {$next=$value+1} }
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('rawset(_G, "BO7EternalFramePacks", {')
$count = 0
foreach($folder in (Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)) {
 $file = Join-Path $folder.FullName 'ui_icon_eternalperk.png'
 if (!(Test-Path -LiteralPath $file)) { Write-Output ('Skipped ' + $folder.Name + ': missing ui_icon_eternalperk.png'); continue }
 if (!$registry.ContainsKey($folder.Name)) { if($next -gt 999) {throw 'Frame pack limit reached'}; $registry[$folder.Name]=$next; $next++ }
 $bitmap=[Drawing.Bitmap]::new($file)
 $width=$bitmap.Width; $height=$bitmap.Height; $bitmap.Dispose()
 $centerX=$width/2.0; $centerY=$height/2.0; $reference=256; $scale='nil'
 $settings=Join-Path $folder.FullName 'frame.json'
 if(Test-Path -LiteralPath $settings) {
  $meta=Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
  if($null -ne $meta.centerX) {$centerX=[double]$meta.centerX}; if($null -ne $meta.centerY) {$centerY=[double]$meta.centerY}
  if($null -ne $meta.referenceSize) {$reference=[double]$meta.referenceSize}
  if($null -ne $meta.scale) {if([double]$meta.scale -le 0) {throw 'Frame scale must be positive'}; $scale=([double]$meta.scale).ToString([Globalization.CultureInfo]::InvariantCulture)}
 }
 if($reference -le 0) {throw 'referenceSize must be positive'}
 $alias='gcp_eternal_frame_' + $registry[$folder.Name]
 Copy-Item -LiteralPath $file -Destination (Join-Path $imageRoot ($alias+'.png')) -Force
 $fmt=[Globalization.CultureInfo]::InvariantCulture
 $lines.Add('{id='+$registry[$folder.Name]+', name='+(Quote-Lua $folder.Name)+', material='+(Quote-Lua $alias)+', width='+$width+', height='+$height+', centerX='+$centerX.ToString($fmt)+', centerY='+$centerY.ToString($fmt)+', referenceSize='+$reference.ToString($fmt)+', scale='+$scale+'},')
 $count++
}
$lines.Add('})')
[IO.File]::WriteAllText((Join-Path $KronosPath 'Assets/Lua/bo7_eternal_frame_packs_post.lua'),($lines -join "`n"),[Text.UTF8Encoding]::new($false))
$registry | ConvertTo-Json | Set-Content -LiteralPath $registryFile -Encoding UTF8
Write-Output ('Imported '+$count+' eternal frame packs. Fully restart the game, then choose FRAME in Custom Perks.')
