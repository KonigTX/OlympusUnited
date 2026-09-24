param(
    [string]$InstallPath
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot "addon\OlympusUnited"
$toc = Join-Path $source "OlympusUnited.toc"
$dist = Join-Path $projectRoot "dist"
$expectedInstall = [System.IO.Path]::GetFullPath("D:\Program Files\World of Warcraft\_classic_beta_\Interface\AddOns\OlympusUnited").TrimEnd('\')

if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Addon TOC not found: $toc" }
$versionLine = Get-Content -LiteralPath $toc | Where-Object { $_ -match '^## Version:\s*(\S+)\s*$' } | Select-Object -First 1
if (-not $versionLine -or $versionLine -notmatch '^## Version:\s*(\S+)\s*$') { throw "TOC version is missing" }
$version = $Matches[1]
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("olympus-united-package-" + [guid]::NewGuid().ToString("N"))
$stageAddon = Join-Path $stageRoot "OlympusUnited"
$archive = Join-Path $dist ("OlympusUnited-" + $version + ".zip")
$checksum = Join-Path $dist ("OlympusUnited-" + $version + ".sha256")

try {
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    New-Item -ItemType Directory -Path $stageAddon | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $stageAddon -Recurse
    Copy-Item -LiteralPath (Join-Path $projectRoot "README.md") -Destination (Join-Path $stageAddon "README.md")
    Copy-Item -LiteralPath (Join-Path $projectRoot "CHANGELOG.md") -Destination (Join-Path $stageAddon "CHANGELOG.md")
    Copy-Item -LiteralPath (Join-Path $projectRoot "LICENSE.txt") -Destination (Join-Path $stageAddon "LICENSE.txt")

    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [System.IO.File]::Open($archive, [System.IO.FileMode]::CreateNew)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $files = Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Sort-Object { $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/') }
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
                $entry = $zip.CreateEntry($relative, [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [System.DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
                $input = [System.IO.File]::OpenRead($file.FullName)
                $output = $entry.Open()
                try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }

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
        foreach ($file in Get-ChildItem -LiteralPath $stageAddon -Recurse -File | Sort-Object FullName) {
            $relative = $file.FullName.Substring($stageAddon.Length + 1)
            $destination = Join-Path $copyRoot $relative
            $destinationDirectory = Split-Path -Parent $destination
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
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
} finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
}
