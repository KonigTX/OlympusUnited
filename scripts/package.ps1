param(
    [string]$InstallPath
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot "addon\OlympusUnited"
$toc = Join-Path $source "OlympusUnited.toc"
$dist = Join-Path $projectRoot "dist"
$expectedInstall = [System.IO.Path]::GetFullPath("D:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\OlympusUnited").TrimEnd('\')
$fixedDosDate = [uint16]0x0021
$fixedDosTime = [uint16]0x0000

if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Addon TOC not found: $toc" }
$versionLine = Get-Content -LiteralPath $toc | Where-Object { $_ -match '^## Version:\s*(\S+)\s*$' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^## Version:\s*(\S+)\s*$') { throw "TOC version is missing" }
$version = $Matches[1]
$archive = Join-Path $dist ("OlympusUnited-" + $version + ".zip")
$checksum = Join-Path $dist ("OlympusUnited-" + $version + ".sha256")

# OlympusUnited.StoredZip.v1 is intentionally small and explicit. Every input is
# mapped to one ASCII entry name, entries are ordinally sorted, bytes are stored
# without compression, and every metadata field is written by this script.
$entries = @(
    [pscustomobject]@{ Source = (Join-Path $source "Census.lua"); Entry = "OlympusUnited/Census.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "CensusLogic.lua"); Entry = "OlympusUnited/CensusLogic.lua" },
    [pscustomobject]@{ Source = (Join-Path $projectRoot "CHANGELOG.md"); Entry = "OlympusUnited/CHANGELOG.md" },
    [pscustomobject]@{ Source = (Join-Path $source "ChatGuard.lua"); Entry = "OlympusUnited/ChatGuard.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "Commands.lua"); Entry = "OlympusUnited/Commands.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "Core.lua"); Entry = "OlympusUnited/Core.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "GuildRoster.lua"); Entry = "OlympusUnited/GuildRoster.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "GuildTrust.lua"); Entry = "OlympusUnited/GuildTrust.lua" },
    [pscustomobject]@{ Source = (Join-Path $projectRoot "LICENSE.txt"); Entry = "OlympusUnited/LICENSE.txt" },
    [pscustomobject]@{ Source = (Join-Path $source "Media\OlympusLogo.tga"); Entry = "OlympusUnited/Media/OlympusLogo.tga" },
    [pscustomobject]@{ Source = (Join-Path $source "Network.lua"); Entry = "OlympusUnited/Network.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "OlympusUnited.toc"); Entry = "OlympusUnited/OlympusUnited.toc" },
    [pscustomobject]@{ Source = (Join-Path $source "Protocol.lua"); Entry = "OlympusUnited/Protocol.lua" },
    [pscustomobject]@{ Source = (Join-Path $projectRoot "README.md"); Entry = "OlympusUnited/README.md" },
    [pscustomobject]@{ Source = (Join-Path $source "State.lua"); Entry = "OlympusUnited/State.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "Strings.lua"); Entry = "OlympusUnited/Strings.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "UI.lua"); Entry = "OlympusUnited/UI.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "UIPrimitives.lua"); Entry = "OlympusUnited/UIPrimitives.lua" },
    [pscustomobject]@{ Source = (Join-Path $source "Util.lua"); Entry = "OlympusUnited/Util.lua" }
)

function Sort-EntriesOrdinal([object[]]$Values) {
    $copy = @($Values)
    for ($index = 1; $index -lt $copy.Count; $index++) {
        $value = $copy[$index]
        $cursor = $index - 1
        while ($cursor -ge 0 -and [System.StringComparer]::Ordinal.Compare($copy[$cursor].Entry, $value.Entry) -gt 0) {
            $copy[$cursor + 1] = $copy[$cursor]
            $cursor--
        }
        $copy[$cursor + 1] = $value
    }
    return $copy
}

function Get-Crc32([byte[]]$Bytes) {
    [uint32]$crc = [uint32]::MaxValue
    [uint32]$polynomial = 3988292384
    foreach ($byte in $Bytes) {
        $crc = [uint32]($crc -bxor [uint32]$byte)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint32](($crc -shr 1) -bxor $polynomial)
            } else {
                $crc = [uint32]($crc -shr 1)
            }
        }
    }
    return [uint32]($crc -bxor [uint32]::MaxValue)
}

function Write-StoredZip([string]$Path, [object[]]$MappedEntries) {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $ordered = Sort-EntriesOrdinal $MappedEntries
    foreach ($item in $ordered) {
        if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) { throw "Package input is missing: $($item.Source)" }
        if ($item.Entry -notmatch '^[\x20-\x7e]+$' -or $item.Entry.Contains('\')) { throw "ZIP entry name is not canonical ASCII: $($item.Entry)" }
        if (-not $seen.Add($item.Entry)) { throw "Duplicate ZIP entry: $($item.Entry)" }
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $writer = New-Object System.IO.BinaryWriter($stream, [System.Text.Encoding]::ASCII, $true)
    $central = @()
    try {
        foreach ($item in $ordered) {
            [byte[]]$name = [System.Text.Encoding]::ASCII.GetBytes($item.Entry)
            [byte[]]$content = [System.IO.File]::ReadAllBytes($item.Source)
            if ([uint64]$content.LongLength -gt [uint32]::MaxValue) { throw "ZIP64 is outside OlympusUnited.StoredZip.v1: $($item.Entry)" }
            [uint32]$offset = $stream.Position
            [uint32]$length = $content.LongLength
            [uint32]$crc = Get-Crc32 $content

            $writer.Write([uint32]0x04034b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write($fixedDosTime)
            $writer.Write($fixedDosDate)
            $writer.Write($crc)
            $writer.Write($length)
            $writer.Write($length)
            $writer.Write([uint16]$name.Length)
            $writer.Write([uint16]0)
            $writer.Write($name)
            $writer.Write($content)
            $central += [pscustomobject]@{ Name = $name; Crc = $crc; Length = $length; Offset = $offset }
        }

        [uint32]$centralOffset = $stream.Position
        foreach ($item in $central) {
            $writer.Write([uint32]0x02014b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write($fixedDosTime)
            $writer.Write($fixedDosDate)
            $writer.Write([uint32]$item.Crc)
            $writer.Write([uint32]$item.Length)
            $writer.Write([uint32]$item.Length)
            $writer.Write([uint16]$item.Name.Length)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint32]0)
            $writer.Write([uint32]$item.Offset)
            $writer.Write([byte[]]$item.Name)
        }
        [uint32]$centralLength = $stream.Position - $centralOffset
        if ($central.Count -gt [uint16]::MaxValue) { throw "Too many ZIP entries" }
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$central.Count)
        $writer.Write([uint16]$central.Count)
        $writer.Write($centralLength)
        $writer.Write($centralOffset)
        $writer.Write([uint16]0)
        $writer.Flush()
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
if (Test-Path -LiteralPath $checksum) { Remove-Item -LiteralPath $checksum -Force }
Write-StoredZip $archive $entries

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText($checksum, "$hash  $([System.IO.Path]::GetFileName($archive))`n", [System.Text.Encoding]::ASCII)

if ($InstallPath) {
    $requested = [System.IO.Path]::GetFullPath($InstallPath).TrimEnd('\')
    if (-not $requested.Equals($expectedInstall, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing install outside exact authorized destination: $requested"
    }
    $installItem = Get-Item -LiteralPath $requested -Force -ErrorAction SilentlyContinue
    if (-not $installItem) {
        New-Item -ItemType Directory -Path $requested | Out-Null
        $installItem = Get-Item -LiteralPath $requested -Force
    }
    $isReparse = ($installItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparse) {
        $linkTarget = @($installItem.Target)[0]
        if (-not $linkTarget) { throw "Could not resolve install reparse point: $requested" }
        if (-not [System.IO.Path]::IsPathRooted($linkTarget)) { $linkTarget = Join-Path $installItem.Parent.FullName $linkTarget }
        $copyRoot = [System.IO.Path]::GetFullPath($linkTarget).TrimEnd('\')
        if (-not (Test-Path -LiteralPath $copyRoot -PathType Container)) { throw "Resolved install target is missing: $copyRoot" }
    } else {
        $resolved = [System.IO.Path]::GetFullPath($installItem.FullName).TrimEnd('\')
        if (-not $resolved.Equals($expectedInstall, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Resolved install path escaped exact authorized destination: $resolved"
        }
        $copyRoot = $requested
        Get-ChildItem -LiteralPath $copyRoot -Recurse -File -Force | Remove-Item -Force
        Get-ChildItem -LiteralPath $copyRoot -Recurse -Directory -Force | Sort-Object FullName -Descending | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $proof = @()
    foreach ($item in Sort-EntriesOrdinal $entries) {
        $relative = $item.Entry.Substring("OlympusUnited/".Length).Replace('/', '\')
        $destination = Join-Path $copyRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $item.Source -Destination $destination -Force
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.Source).Hash.ToLowerInvariant()
        $installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
        if ($sourceHash -ne $installedHash) { throw "Installed hash mismatch: $relative" }
        $proof += [pscustomobject]@{ File = $relative.Replace('\', '/'); SHA256 = $installedHash }
    }
    Write-Output ("INSTALL_ROOT " + $requested)
    Write-Output ("INSTALL_REPARSE " + $isReparse)
    Write-Output ("INSTALL_RESOLVED " + $copyRoot)
    $proof | Format-Table -AutoSize
}

Get-Item -LiteralPath $archive, $checksum
