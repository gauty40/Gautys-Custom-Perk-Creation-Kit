param([string]$KronosPath = (Join-Path $PSScriptRoot 'kronos'))
$ErrorActionPreference = 'Stop'
$KronosPath = [IO.Path]::GetFullPath($KronosPath)
$imageRoot = Join-Path $KronosPath 'Assets/Images'
$packRoot = Join-Path $imageRoot 'perks'
$luaRoot = Join-Path $KronosPath 'Assets/Lua'
$main = Get-Content -LiteralPath (Join-Path $luaRoot 'bo7_custom_perks_post.lua') -Raw
$customSection = [regex]::Match($main, 'local CUSTOM = \{([\s\S]*?)\n\}').Value
$names = @([regex]::Matches($customSection, 'icon\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
function Quote-Lua([string]$Value) { return '"' + $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n') + '"' }
$selected = 'Black Ops 7'
$config = Join-Path $KronosPath 'perk_icons.cfg'
if (Test-Path -LiteralPath $config) { $selected = (Get-Content -LiteralPath $config -Raw).Trim() }
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('rawset(_G, "BO7CustomPerkIconPacks", { defaultPack = ' + (Quote-Lua $selected) + ', packs = {')
$count = 0
foreach ($pack in (Get-ChildItem -LiteralPath $packRoot -Directory)) {
 $entries = [Collections.Generic.List[string]]::new()
 foreach ($name in $names) {
  $source = Join-Path $pack.FullName ($name + '.png')
  if (!(Test-Path -LiteralPath $source)) { continue }
  $sha = [Security.Cryptography.SHA256]::Create()
  $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($pack.Name + '/' + $name))).Replace('-','').ToLowerInvariant()
  $sha.Dispose()
  $material = 'gcp_pack_' + $hash.Substring(0,20)
  Copy-Item -LiteralPath $source -Destination (Join-Path $imageRoot ($material + '.png')) -Force
  $entries.Add('[' + (Quote-Lua $name) + '] = ' + (Quote-Lua $material))
  $count++
 }
 if ($entries.Count -gt 0) { $lines.Add('[' + (Quote-Lua $pack.Name.ToLowerInvariant()) + '] = {' + ($entries -join ', ') + '},') }
}
$lines.Add('} })')
[IO.File]::WriteAllText((Join-Path $luaRoot 'bo7_custom_perk_pack_assets_post.lua'), ($lines -join "`n"), [Text.UTF8Encoding]::new($false))
Write-Output ('Imported ' + $count + ' custom pack images. Restart the game after importing new images.')
