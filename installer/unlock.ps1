# SHODAN HD1 Editor: Unlock Everything. Edits the HELLDIVERS save offline: every item that isn't
# paid DLC unlocked, every upgrade bought (owned DLC items included). XP, rank and samples untouched.
# The save is a dumped Lua table (value then key, tables 0..1), zlib'd in 64 KB chunks with a CRC32.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($s) { Write-Host $s }

# --- data (from the game's own settings: PlanetRewardSettings, ProgressionSettings, CustomizationSettings, LoadoutSettings)
$items = Get-Content -LiteralPath (Join-Path $here "unlock_items.txt") | Where-Object { $_ }
$upgrades = [ordered]@{}
foreach ($l in Get-Content -LiteralPath (Join-Path $here "unlock_upgrades.txt")) {
	if ($l -match '^(\w+)=(\d+)$') { $upgrades[$matches[1]] = [double]$matches[2] }
}

# --- CRC32 and Adler-32 (in [long]: PowerShell reads 0xFFFFFFFF as -1)
$crcTable = New-Object 'long[]' 256
for ($i = 0; $i -lt 256; $i++) {
	[long]$c = $i
	for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = 3988292384 -bxor ($c -shr 1) } else { $c = $c -shr 1 } }
	$crcTable[$i] = $c
}
function Crc32([byte[]]$b, [int]$start) {
	[long]$c = 4294967295
	for ($i = $start; $i -lt $b.Length; $i++) { $c = $crcTable[($c -bxor $b[$i]) -band 255] -bxor ($c -shr 8) }
	return [uint32]($c -bxor 4294967295)
}
function Adler32([byte[]]$b) {
	[long]$a = 1; [long]$s = 0
	foreach ($x in $b) { $a = ($a + $x) % 65521; $s = ($s + $a) % 65521 }
	return [uint32](($s -shl 16) -bor $a)
}

# --- container
$MAGIC = "D4-FD-1C-6B-5F-7B-23-CC"
function Read-Save([byte[]]$d) {
	if ([BitConverter]::ToString($d, 0, 8) -ne $MAGIC) { throw "not a HELLDIVERS save" }
	if ((Crc32 $d 16) -ne [BitConverter]::ToUInt32($d, 12)) { throw "the save's checksum doesn't match" }
	$raw = New-Object System.IO.MemoryStream
	$p = 32
	while ($p -lt $d.Length) {
		$n = [BitConverter]::ToInt32($d, $p)
		$ms = [System.IO.MemoryStream]::new($d, $p + 6, $n - 6)
		$z = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
		$z.CopyTo($raw); $z.Dispose()
		$p += 4 + $n
	}
	return , $raw.ToArray()
}
function Write-Save([byte[]]$raw, [int]$logical) {
	$out = New-Object System.IO.MemoryStream
	$out.Write((New-Object byte[] 32), 0, 32)
	for ($o = 0; $o -lt $raw.Length; $o += 65536) {
		$chunk = New-Object byte[] 65536
		[Array]::Copy($raw, $o, $chunk, 0, [Math]::Min(65536, $raw.Length - $o))
		$ms = New-Object System.IO.MemoryStream
		$z = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress, $true)
		$z.Write($chunk, 0, $chunk.Length); $z.Dispose()
		$body = $ms.ToArray()
		$ad = [BitConverter]::GetBytes((Adler32 $chunk)); [Array]::Reverse($ad)
		$out.Write([BitConverter]::GetBytes([int]($body.Length + 6)), 0, 4)
		$out.Write([byte[]](0x78, 0x9c), 0, 2); $out.Write($body, 0, $body.Length); $out.Write($ad, 0, 4)
	}
	$d = $out.ToArray()
	[Array]::Copy([byte[]](0xd4, 0xfd, 0x1c, 0x6b, 0x5f, 0x7b, 0x23, 0xcc), 0, $d, 0, 8)
	[Array]::Copy([BitConverter]::GetBytes([int]1), 0, $d, 8, 4)
	[Array]::Copy([BitConverter]::GetBytes([int]($d.Length - 24)), 0, $d, 16, 4)
	[Array]::Copy([BitConverter]::GetBytes([int]$logical), 0, $d, 20, 4)
	[Array]::Copy([BitConverter]::GetBytes([int]$logical), 0, $d, 24, 4)
	[Array]::Copy([BitConverter]::GetBytes((Crc32 $d 16)), 0, $d, 12, 4)
	return , $d
}

# --- the Lua table inside. Tables are ordered lists of @(key, value) so the save keeps its order.
$script:u = $null
$script:p = 0
function Read-Value {
	$script:p = ($script:p + 3) -band -4
	$t = [BitConverter]::ToInt32($script:u, $script:p); $script:p += 4
	switch ($t) {
		0 {
			$list = New-Object System.Collections.ArrayList
			while ([BitConverter]::ToInt32($script:u, $script:p) -ne 1) {
				$v = Read-Value; $k = Read-Value
				[void]$list.Add(@($k, $v))
			}
			$script:p += 4
			return , $list
		}
		3 { $n = [BitConverter]::ToInt32($script:u, $script:p); $s = [Text.Encoding]::UTF8.GetString($script:u, $script:p + 4, $n); $script:p += 4 + $n; return $s }
		4 { $b = $script:u[$script:p] -ne 0; $script:p += 4; return $b }
		9 { $script:p = ($script:p + 7) -band -8; $v = [BitConverter]::ToDouble($script:u, $script:p); $script:p += 8; return $v }
		default { throw ("unknown value type {0} in the save" -f $t) }
	}
}
function Write-Value($w, $v) {
	function Pad($n) { while ($w.Length % $n) { $w.WriteByte(0) } }
	function Tag($t) { Pad 4; $w.Write([BitConverter]::GetBytes([int]$t), 0, 4) }
	if ($v -is [System.Collections.ArrayList]) {
		Tag 0
		foreach ($kv in $v) { Write-Value $w $kv[1]; Write-Value $w $kv[0] }
		$w.Write([BitConverter]::GetBytes([int]1), 0, 4)  # the end tag is written unaligned
	} elseif ($v -is [bool]) { Tag 4; $w.Write([byte[]]([byte][int]$v, 0, 0, 0), 0, 4) }
	elseif ($v -is [string]) { Tag 3; $e = [Text.Encoding]::UTF8.GetBytes($v); $w.Write([BitConverter]::GetBytes([int]$e.Length), 0, 4); $w.Write($e, 0, $e.Length) }
	else { Tag 9; Pad 8; $w.Write([BitConverter]::GetBytes([double]$v), 0, 8) }
}
function Find($t, $key) { foreach ($kv in $t) { if ($kv[0] -eq $key) { return , $kv } } return $null }

function Unlock-File($path) {
	$raw = Read-Save ([IO.File]::ReadAllBytes($path))
	$script:u = $raw; $script:p = 0x18
	$root = Read-Value
	$unl = Find $root "item_unlocks"
	$upg = Find $root "item_upgrades_02"
	if (-not $unl -or -not $upg) { return $false }
	$new = Find $root "new_unlocks"
	$have = @{}
	foreach ($kv in $unl[1]) { $have[$kv[1]] = $true }
	$added = 0
	foreach ($name in $items) {
		if ($have[$name]) { continue }
		[void]$unl[1].Add(@([double]($unl[1].Count + 1), $name))
		if ($new) { [void]$new[1].Add(@([double]($new[1].Count + 1), $name)) }
		$have[$name] = $true; $added++
	}
	$raised = 0
	foreach ($name in $upgrades.Keys) {
		$kv = Find $upg[1] $name
		if ($kv) { if ($kv[1] -lt $upgrades[$name]) { $kv[1] = $upgrades[$name]; $raised++ } }
		else { [void]$upg[1].Add(@($name, $upgrades[$name])); $raised++ }
	}
	$w = New-Object System.IO.MemoryStream
	$w.Write($raw, 0, 0x18)
	Write-Value $w $root
	$body = $w.ToArray()
	[Array]::Copy([BitConverter]::GetBytes([int]($body.Length - 0x18)), 0, $body, 8, 4)
	$size = [int]([Math]::Ceiling($body.Length / 65536) * 65536)
	$padded = New-Object byte[] $size
	[Array]::Copy($body, $padded, $body.Length)
	[IO.File]::WriteAllBytes($path, (Write-Save $padded $body.Length))
	Say ("  {0} items unlocked, {1} upgrades bought" -f $added, $raised)
	return $true
}

# --- a test run on one file: unlock.ps1 <save path>
if ($args.Count -gt 0) { [void](Unlock-File $args[0]); exit 0 }

# --- find the saves
if (Get-Process -Name "helldivers" -ErrorAction SilentlyContinue) { Say "Close HELLDIVERS first, then run this again."; exit 1 }
$steam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
if (-not $steam) { $steam = "${env:ProgramFiles(x86)}\Steam" }
$saves = @(Get-ChildItem -Path (Join-Path $steam "userdata\*\394510\remote\helldivers_save*") -ErrorAction SilentlyContinue |
	Where-Object { $_.Name -match '^helldivers_save[0-9a-f]+$' })
if (-not $saves) { Say "No HELLDIVERS save found. Start the game once, reach your ship, then quit and run this again."; exit 1 }

$backup = Join-Path $env:LOCALAPPDATA ("SHODAN\SHD1Editor\backup\save-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
$done = 0
foreach ($f in $saves) {
	$account = $f.Directory.Parent.Parent.Name
	New-Item -ItemType Directory -Force -Path (Join-Path $backup $account) | Out-Null
	Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $backup $account)
	Say ("Save of Steam account {0}:" -f $account)
	try { if (Unlock-File $f.FullName) { $done++ } else { Say "  not a player save, left alone" } }
	catch { Copy-Item -LiteralPath (Join-Path (Join-Path $backup $account) $f.Name) -Destination $f.FullName -Force; Say ("  failed, save left as it was: " + $_) }
}
Say ""
if ($done) { Say "Done. Your rank and XP are as they were. The old save is in $backup" } else { Say "Nothing was changed." }
