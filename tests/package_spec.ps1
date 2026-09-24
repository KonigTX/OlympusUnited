$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$tempRoot = Join-Path $tempBase ("olympus-united-package-spec-" + [guid]::NewGuid().ToString("N"))
$tempRoot = [System.IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
if ((-not $tempRoot.StartsWith($tempBase + '\', [System.StringComparison]::OrdinalIgnoreCase)) -or (-not ([System.IO.Path]::GetFileName($tempRoot)).StartsWith("olympus-united-package-spec-", [System.StringComparison]::Ordinal))) {
    throw "Refusing unsafe package test root: $tempRoot"
}

$declaredInputs = @(
    "scripts/package.ps1",
    "README.md", "CHANGELOG.md", "LICENSE.txt",
    "addon/OlympusUnited/Census.lua",
    "addon/OlympusUnited/CensusLogic.lua",
    "addon/OlympusUnited/ChatGuard.lua",
    "addon/OlympusUnited/Commands.lua",
    "addon/OlympusUnited/Core.lua",
    "addon/OlympusUnited/GuildRoster.lua",
    "addon/OlympusUnited/GuildTrust.lua",
    "addon/OlympusUnited/Media/OlympusLogo.tga",
    "addon/OlympusUnited/Network.lua",
    "addon/OlympusUnited/OlympusUnited.toc",
    "addon/OlympusUnited/Protocol.lua",
    "addon/OlympusUnited/State.lua",
    "addon/OlympusUnited/Strings.lua",
    "addon/OlympusUnited/UI.lua",
    "addon/OlympusUnited/UIPrimitives.lua",
    "addon/OlympusUnited/Util.lua"
)

function Copy-DeclaredInputs([string]$DestinationRoot) {
    foreach ($relative in $declaredInputs) {
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Declared package input missing: $relative" }
        $destination = Join-Path $DestinationRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }
}

function Invoke-IsolatedPackage([string]$Shell, [string]$Root) {
    & $Shell -NoProfile -File (Join-Path $Root "scripts\package.ps1") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$Shell package build failed with exit $LASTEXITCODE" }
    $archive = Join-Path $Root "dist\OlympusUnited-0.6.0.zip"
    $sidecar = Join-Path $Root "dist\OlympusUnited-0.6.0.sha256"
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf) -or -not (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
        throw "$Shell did not produce the isolated archive and sidecar"
    }
    return [pscustomobject]@{ Archive = $archive; Sidecar = $sidecar }
}

function Expected-Source([string]$Root, [string]$EntryName) {
    $relative = $EntryName.Substring("OlympusUnited/".Length)
    if ($relative -eq "README.md" -or $relative -eq "CHANGELOG.md" -or $relative -eq "LICENSE.txt") {
        return Join-Path $Root $relative
    }
    return Join-Path $Root ("addon\OlympusUnited\" + $relative.Replace('/', '\'))
}

function Assert-CanonicalArchive([string]$Root, [string]$ArchivePath, [string]$SidecarPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [System.IO.File]::OpenRead($ArchivePath)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName })
            for ($index = 1; $index -lt $names.Count; $index++) {
                if ([System.StringComparer]::Ordinal.Compare($names[$index - 1], $names[$index]) -ge 0) {
                    throw "ZIP entries are not unique ordinal order"
                }
            }
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -notmatch '^[\x20-\x7e]+$' -or $entry.FullName.Contains('\')) {
                    throw "Non-canonical entry name: $($entry.FullName)"
                }
                if ($entry.LastWriteTime.Year -ne 1980 -or $entry.LastWriteTime.Month -ne 1 -or $entry.LastWriteTime.Day -ne 1 -or $entry.LastWriteTime.Hour -ne 0 -or $entry.LastWriteTime.Minute -ne 0 -or $entry.LastWriteTime.Second -ne 0) {
                    throw "Non-canonical timestamp: $($entry.FullName)"
                }
                if ($entry.ExternalAttributes -ne 0) { throw "Non-canonical external attributes: $($entry.FullName)" }
                if ($entry.CompressedLength -ne $entry.Length) { throw "Entry is not stored: $($entry.FullName)" }
                $source = Expected-Source $Root $entry.FullName
                if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Mapped source missing: $($entry.FullName)" }
                $entryStream = $entry.Open()
                $memory = New-Object System.IO.MemoryStream
                try { $entryStream.CopyTo($memory) } finally { $entryStream.Dispose() }
                try {
                    $sourceBytes = [System.IO.File]::ReadAllBytes($source)
                    $entryBytes = $memory.ToArray()
                    if ($sourceBytes.Length -ne $entryBytes.Length) { throw "Entry length mismatch: $($entry.FullName)" }
                    for ($index = 0; $index -lt $sourceBytes.Length; $index++) {
                        if ($sourceBytes[$index] -ne $entryBytes[$index]) { throw "Entry content mismatch: $($entry.FullName)" }
                    }
                } finally { $memory.Dispose() }
            }

            $tocEntry = $zip.GetEntry("OlympusUnited/OlympusUnited.toc")
            $licenseEntry = $zip.GetEntry("OlympusUnited/LICENSE.txt")
            if (-not $tocEntry -or -not $licenseEntry) { throw "Identity entries missing" }
            $tocReader = New-Object System.IO.StreamReader($tocEntry.Open())
            try { $tocText = $tocReader.ReadToEnd() } finally { $tocReader.Dispose() }
            $licenseReader = New-Object System.IO.StreamReader($licenseEntry.Open())
            try { $licenseText = $licenseReader.ReadToEnd() } finally { $licenseReader.Dispose() }
            if ($tocText -cnotmatch '(?m)^## Author: KonigTX$' -or $licenseText -cnotmatch '(?m)^Copyright \(c\) 2026 KonigTX$') {
                throw "Exact KonigTX identity is missing from archive entries"
            }
            if ($tocText -cmatch 'Konigtx' -or $licenseText -cmatch 'Konigtx') { throw "Residual Konigtx identity found" }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToLowerInvariant()
    $expectedLine = "$hash  $([System.IO.Path]::GetFileName($ArchivePath))`n"
    $actualLine = [System.IO.File]::ReadAllText($SidecarPath, [System.Text.Encoding]::ASCII)
    if ($actualLine -cne $expectedLine) { throw "Sidecar is not one canonical ASCII LF line" }
}

try {
    $windowsRoot = Join-Path $tempRoot "windows-powershell"
    $pwshRoot = Join-Path $tempRoot "pwsh"
    New-Item -ItemType Directory -Path $windowsRoot, $pwshRoot | Out-Null
    Copy-DeclaredInputs $windowsRoot
    Copy-DeclaredInputs $pwshRoot

    $windows = Invoke-IsolatedPackage "powershell.exe" $windowsRoot
    $modern = Invoke-IsolatedPackage "pwsh" $pwshRoot
    Assert-CanonicalArchive $windowsRoot $windows.Archive $windows.Sidecar
    Assert-CanonicalArchive $pwshRoot $modern.Archive $modern.Sidecar

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $windows.Archive).Hash -cne (Get-FileHash -Algorithm SHA256 -LiteralPath $modern.Archive).Hash) {
        throw "Windows PowerShell and pwsh archive bytes differ"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $windows.Sidecar).Hash -cne (Get-FileHash -Algorithm SHA256 -LiteralPath $modern.Sidecar).Hash) {
        throw "Windows PowerShell and pwsh sidecar bytes differ"
    }
    Write-Output "Olympus United package tests passed"
} finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
    if (($resolved.StartsWith($tempBase + '\', [System.StringComparison]::OrdinalIgnoreCase)) -and (([System.IO.Path]::GetFileName($resolved)).StartsWith("olympus-united-package-spec-", [System.StringComparison]::Ordinal)) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
