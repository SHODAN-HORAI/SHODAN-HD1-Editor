# SHODAN HD1 Editor installer. installer.ps1 install|remove
# Puts the editor's patch file in the game's contents folder. Patch files there that aren't ours (another
# mod's, at any patch level) are backed up first and everything in them goes into ours, their boot chunk
# run after ours, so those mods keep working beside the editor.
param([string]$Action = "install")
$ErrorActionPreference = "Stop"

$Name = "9cf71054ea26dddf.patch_0"
$Base = "9cf71054ea26dddf"
$FgwCore = [Convert]::ToUInt64("0caefbeadd82700b", 16)   # murmur64("fgw/core"): marks our patch
$BootName = [Convert]::ToUInt64("35546153a5bb59d2", 16)  # foundation/lua/build_date_information
$ChainName = [Convert]::ToUInt64("0776dd65fac5026d", 16) # fgw/chain: the other mod's boot chunk
$Lua = [Convert]::ToUInt64("a14e8dfa2cd117e2", 16)
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Folder = Join-Path $env:LOCALAPPDATA "SHODAN\SHD1Editor"
$Backup = Join-Path $Folder "backup\$Name"
# The folder of the editor's old name (FGW Editor), with its edits, presets and backup.
$OldFolder = Join-Path $env:LOCALAPPDATA "SHODAN\FGWEditor"
if ((Test-Path $OldFolder) -and -not (Test-Path $Folder)) { Move-Item $OldFolder $Folder }

function Find-Game {
	$libs = @()
	$steam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
	if ($steam) {
		$libs += $steam
		$vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
		if (Test-Path $vdf) {
			foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value -replace '\\\\', '\' }
		}
	}
	foreach ($lib in $libs) {
		$c = Join-Path $lib "steamapps\common\Helldivers\contents"
		if (Test-Path (Join-Path $c $Base)) { return $c }
	}
	Add-Type -AssemblyName System.Windows.Forms
	$d = New-Object System.Windows.Forms.FolderBrowserDialog
	$d.Description = "Couldn't find HELLDIVERS. Pick its folder (the one holding 'contents')."
	if ($d.ShowDialog() -eq "OK") {
		$c = Join-Path $d.SelectedPath "contents"
		if (Test-Path (Join-Path $c $Base)) { return $c }
	}
	throw "HELLDIVERS wasn't found."
}

# A bundle: a 12-byte header, then 64 KiB chunks, each zlib or (at exactly 65536 bytes) stored as is.
function Unpack([byte[]]$raw) {
	$size = [BitConverter]::ToUInt32($raw, 4)
	$out = New-Object System.IO.MemoryStream
	$o = 12
	while ($o -lt $raw.Length -and $out.Length -lt $size) {
		$n = [BitConverter]::ToUInt32($raw, $o); $o += 4
		if ($n -eq 65536) { $out.Write($raw, $o, $n) }
		else {
			# zlib: a 2-byte header, raw deflate, a 4-byte check.
			$src = New-Object System.IO.MemoryStream($raw, ($o + 2), ($n - 2))
			$z = New-Object System.IO.Compression.DeflateStream($src, [System.IO.Compression.CompressionMode]::Decompress)
			$z.CopyTo($out); $z.Dispose()
		}
		$o += $n
	}
	$out.SetLength($size)
	return , $out.ToArray()
}

# Resources: name and the whole record (type, name, variants, heads, data), kept as bytes.
function Parse([byte[]]$d) {
	$count = [BitConverter]::ToUInt32($d, 0)
	$o = 260 + $count * 16
	$res = @()
	for ($i = 0; $i -lt $count; $i++) {
		$start = $o
		$name = [BitConverter]::ToUInt64($d, $o + 8)
		$vc = [BitConverter]::ToUInt32($d, $o + 16)
		$o += 24
		$sizes = 0
		for ($v = 0; $v -lt $vc; $v++) { $sizes += [BitConverter]::ToUInt32($d, $o + $v * 12 + 4) }
		$o += 12 * $vc + $sizes
		$bytes = New-Object byte[] ($o - $start)
		[Array]::Copy($d, $start, $bytes, 0, $o - $start)
		$res += , @{ type = [BitConverter]::ToUInt64($d, $start); name = $name; bytes = $bytes }
	}
	$block = New-Object byte[] 256
	[Array]::Copy($d, 4, $block, 0, 256)
	return @{ block = $block; res = $res }
}

# Written back with every chunk stored as is: the game's own bundles have such chunks.
function Pack($block, $res) {
	$inner = New-Object System.IO.MemoryStream
	$w = New-Object System.IO.BinaryWriter($inner)
	$w.Write([UInt32]$res.Count); $w.Write([byte[]]$block)
	foreach ($r in $res) { $w.Write([UInt64]$r.type); $w.Write([UInt64]$r.name) }
	foreach ($r in $res) { $w.Write([byte[]]$r.bytes) }
	$w.Flush()
	$d = $inner.ToArray()
	$out = New-Object System.IO.MemoryStream
	$o = New-Object System.IO.BinaryWriter($out)
	$o.Write([UInt32]4026531844); $o.Write([UInt32]$d.Length); $o.Write([UInt32]0)
	for ($i = 0; $i -lt $d.Length; $i += 65536) {
		$chunk = New-Object byte[] 65536
		[Array]::Copy($d, $i, $chunk, 0, [Math]::Min(65536, $d.Length - $i))
		$o.Write([UInt32]65536); $o.Write($chunk)
	}
	$o.Flush()
	return , $out.ToArray()
}

# One Lua resource: type, name, one variant (language 0, size, no stream), then the data.
function Lua-Record([UInt64]$name, [byte[]]$data) {
	$m = New-Object System.IO.MemoryStream
	$w = New-Object System.IO.BinaryWriter($m)
	$w.Write([UInt64]$Lua); $w.Write($name); $w.Write([UInt32]1); $w.Write([UInt32]0)
	$w.Write([UInt32]0); $w.Write([UInt32]$data.Length); $w.Write([UInt32]0); $w.Write($data)
	$w.Flush()
	return @{ type = $Lua; name = $name; bytes = $m.ToArray() }
}

function Read-Bundle($path) { return Parse (Unpack ([IO.File]::ReadAllBytes($path))) }

function Is-Ours($path) {
	foreach ($r in (Read-Bundle $path).res) { if ($r.name -eq $FgwCore) { return $true } }
	return $false
}

# The game's patch levels for our bundle (patch_0, patch_1, ...) in one folder, lowest first. The game
# loads them in that order, so a later level wins (Obsidian writes patch_1 when patch_0 isn't its own).
function Levels($dir) {
	return @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^$Base\.patch_(\d+)$" } |
		Sort-Object { [int]($_.Name -replace '^.*_', '') })
}

function Install($contents) {
	$dir = Split-Path $Backup
	New-Item -ItemType Directory -Force $dir | Out-Null
	$target = Join-Path $contents $Name
	foreach ($f in (Levels $contents)) {
		if (Is-Ours $f.FullName) { continue }
		Copy-Item $f.FullName (Join-Path $dir $f.Name) -Force
		# Higher levels would load over ours and hide the editor: they go inside ours instead.
		if ($f.Name -ne $Name) { Remove-Item $f.FullName -Force }
		Write-Host "Backed up $($f.Name) (another mod's)."
	}
	$mine = [IO.File]::ReadAllBytes((Join-Path $Here $Name))
	$others = Levels $dir
	if ($others.Count) {
		$ours = Parse (Unpack $mine)
		$names = @{}
		foreach ($r in $ours.res) { $names[$r.name] = $true }
		$all = @()
		foreach ($r in $ours.res) {
			if ($r.name -eq $BootName) { $r = Lua-Record $BootName ([IO.File]::ReadAllBytes((Join-Path $Here "boot_chain.bin"))) }
			$all += , $r
		}
		# Every level's files, a higher level's copy replacing a lower one's, as the game would load them.
		$foreign = [ordered]@{}
		foreach ($f in $others) {
			foreach ($r in (Read-Bundle $f.FullName).res) {
				if ($r.name -eq $BootName) {
					# Its boot chunk, under our name for it.
					[Array]::Copy([BitConverter]::GetBytes([UInt64]$ChainName), 0, $r.bytes, 8, 8)
					$r.name = $ChainName
				} elseif ($names[$r.name]) { continue }
				$foreign["$($r.type)-$($r.name)"] = $r
			}
		}
		$all += @($foreign.Values)
		$kept = $foreign.Count
		$mine = Pack $ours.block @($all | Sort-Object { $_.name })
		Write-Host "Kept the other mod's patch file inside ours ($kept files), so it keeps working."
	}
	[IO.File]::WriteAllBytes($target, $mine)
	# Where the game is, for the editor's own updater, and which development build this is (none for a release).
	New-Item -ItemType Directory -Force (Join-Path $Folder "update") | Out-Null
	$commit = Join-Path $Folder "update\commit.txt"
	if (Test-Path (Join-Path $Here "commit.txt")) { Copy-Item (Join-Path $Here "commit.txt") $commit -Force }
	elseif (Test-Path $commit) { Remove-Item $commit -Force }
	[IO.File]::WriteAllText((Join-Path $Folder "game.txt"), $contents)
	if (Test-Path (Join-Path $Folder "updater.ps1")) { Remove-Item (Join-Path $Folder "updater.ps1") -Force }
	Write-Host "SHODAN HD1 Editor is installed. Start HELLDIVERS and press F7."
}

function Remove($contents) {
	$target = Join-Path $contents $Name
	$dir = Split-Path $Backup
	if ((Test-Path $target) -and -not (Is-Ours $target)) {
		# Another mod manager wrote its own since: that one stays, and the old backups are out of date.
		foreach ($f in (Levels $dir)) { Remove-Item $f.FullName -Force }
		Write-Host "SHODAN HD1 Editor wasn't installed (another mod's patch file is there). Nothing changed."
		return
	}
	if (Test-Path $target) { Remove-Item $target -Force }
	foreach ($f in (Levels $dir)) {
		$to = Join-Path $contents $f.Name
		# A level another mod wrote since is newer than our backup of it: that one stays.
		if (-not (Test-Path $to)) { Copy-Item $f.FullName $to -Force; Write-Host "Put $($f.Name) back (another mod's)." }
		Remove-Item $f.FullName -Force
	}
	# The game stops at the first missing level, so a patch_1 with no patch_0 would never load: close the gaps.
	$n = 0
	foreach ($f in (Levels $contents)) {
		$want = "$Base.patch_$n"
		if ($f.Name -ne $want) { Move-Item $f.FullName (Join-Path $contents $want); Write-Host "Moved $($f.Name) to $want so the game loads it. If it's a mod manager's, deploy again there." }
		$n++
	}
	Write-Host "SHODAN HD1 Editor is removed. Your saved edits and presets stay in $Folder."
}

try {
	if ($env:FGW_CONTENTS) { $contents = $env:FGW_CONTENTS } else { $contents = Find-Game }  # FGW_CONTENTS: for the test
	if (Get-Process -Name "helldivers" -ErrorAction SilentlyContinue) { throw "Close HELLDIVERS first." }
	if ($Action -eq "remove") { Remove $contents } else { Install $contents }
} catch {
	Write-Host ("Didn't work: " + $_.Exception.Message) -ForegroundColor Red
	if ($_.Exception -is [UnauthorizedAccessException]) { Write-Host "Right-click the .bat file and pick 'Run as administrator'." }
}
