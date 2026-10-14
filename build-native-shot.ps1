param(
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [Parameter(Mandatory = $true)][string]$AdsJar,
    [Parameter(Mandatory = $true)][string]$ViewpointJar,
    [string]$DeployRoot,
    [switch]$StageOnly,
    [switch]$SkipVerification,
    [string]$JavaExe,
    [string]$CompilerJar,
    [string]$JavacExe,
    [string]$FallbackJar,
    [string]$JavaLanguageLevel = '25'
)
$ErrorActionPreference = 'Stop'
foreach ($requiredPath in @($GameRoot, $AdsJar, $ViewpointJar)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Required build dependency not found: $requiredPath"
    }
}
function Assert-GameClosed {
    if (Get-Process -Name ProjectZomboid64, ProjectZomboid32 -ErrorAction SilentlyContinue) {
        throw 'Close Project Zomboid completely before updating its loaded Java jars.'
    }
}
if (!$StageOnly) { Assert-GameClosed }
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('gael-native-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $buildRoot | Out-Null
$javaPath = if ($JavaExe) { $JavaExe } else { Join-Path $GameRoot 'jre64\bin\java.exe' }
if (!(Test-Path -LiteralPath $javaPath)) { throw "Java runtime not found: $javaPath (pass -JavaExe if needed)" }
$javacPath = if ($JavacExe) { $JavacExe } else { Join-Path (Split-Path $javaPath) 'javac.exe' }
$baseJar = Join-Path $PSScriptRoot 'Contents\mods\ViewpointGaelCompat\42\media\java\client\ViewpointGaelCompat.jar'
$apiJars = @((Join-Path $GameRoot 'projectzomboid.jar'), (Join-Path $GameRoot 'ZombieBuddy.jar'), $AdsJar, $ViewpointJar, $baseJar)
foreach ($apiJar in $apiJars) {
    if (!(Test-Path -LiteralPath $apiJar)) { throw "Required API jar not found: $apiJar" }
}
$classPath = $apiJars -join ';'
$sources = @('src\pvads\GaelNativeShot.java', 'src\pvads\GaelWeaponMotion.java', 'src\pvads\GaelImpactMarker.java', 'src\viewpointgael\Patch_WeaponMotion.java', 'src\viewpointgael\HoldSway.java', 'src\viewpointgael\Patch_HoldSway.java', 'src\pvads\GaelBarrelRay.java', 'src\viewpointgael\AimProbe.java', 'src\viewpointgael\Patch_NativeShot.java', 'src\viewpointgael\Patch_TBDeflect.java', 'src\viewpointgael\Patch_TBMuzzle.java', 'src\viewpointgael\Patch_TBLaunch.java', 'src\viewpointgael\Patch_TBProjectileGuide.java', 'src\viewpointgael\Patch_AimClickFreeCursor.java', 'src\viewpointgael\Patch_TBImpact.java', 'src\viewpointgael\Patch_TBWorldImpact.java', 'src\viewpointgael\Patch_TBExpire.java', 'src\viewpointgael\Patch_TBShot.java', 'src\viewpointgael\Patch_ImpactCamera.java', 'src\viewpoint\input\ThirdPerson.java', 'src\viewpointgael\Main.java', 'src\viewpointgael\Patch_ViewpointThirdPerson.java', 'src\viewpointgael\Patch_ADSThirdPerson.java', 'src\viewpointgael\Patch_ADSSlideNullModel.java', 'tests\GaelNativeShotTest.java', 'tests\GaelMirroredShotTest.java', 'tests\GaelLuaRecoilTest.java', 'tests\GaelPhysicalAxisTest.java', 'tests\GaelWeaponPivotTest.java') | ForEach-Object { Join-Path $PSScriptRoot $_ }
if ($CompilerJar) {
    if (!(Test-Path -LiteralPath $CompilerJar)) { throw "Compiler jar not found: $CompilerJar" }
    & $javaPath -jar $CompilerJar "-$JavaLanguageLevel" -proc:none -classpath $classPath -d $buildRoot @sources
} elseif (Test-Path -LiteralPath $javacPath) {
    & $javacPath --release $JavaLanguageLevel -proc:none -classpath $classPath -d $buildRoot @sources
} else {
    throw "Java compiler not found: $javacPath (pass -JavacExe or -CompilerJar)"
}
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }
if (!$SkipVerification) {
    & $javaPath -cp "$buildRoot;$classPath" pvads.GaelNativeShotTest
    if ($LASTEXITCODE -ne 0) { throw 'Native shot verification failed' }
    & $javaPath -cp "$buildRoot;$classPath" pvads.GaelMirroredShotTest
    if ($LASTEXITCODE -ne 0) { throw 'Mirrored shot verification failed' }
    & $javaPath -cp "$buildRoot;$classPath" pvads.GaelPhysicalAxisTest
    if ($LASTEXITCODE -ne 0) { throw 'Physical axis verification failed' }
    & $javaPath -cp "$buildRoot;$classPath" viewpointgael.GaelWeaponPivotTest
    if ($LASTEXITCODE -ne 0) { throw 'Weapon pivot verification failed' }
    Push-Location $GameRoot
    try {
        $luaRoot = Join-Path $PSScriptRoot 'Contents\mods\ViewpointGaelCompat\42\media\lua\client'
        & $javaPath -cp "$buildRoot;$classPath" GaelLuaRecoilTest "$luaRoot\PVADS_GaelWeaponCatalog.lua" "$luaRoot\PVADS_GaelAlignment.lua" "$luaRoot\PVADS_GaelRecoilBalance.lua" "$luaRoot\PVADS_GaelIronFocus.lua"
        if ($LASTEXITCODE -ne 0) { throw 'Lua recoil balance verification failed' }
    } finally { Pop-Location }
}
# Update only these classes; the existing jar includes additional patches
# whose source is not yet in this repository. Never rebuild it from src alone.
$stagedJar = Join-Path $buildRoot "ViewpointGaelCompat.jar"
$archiveSource = [System.IO.Compression.ZipFile]::OpenRead($baseJar)
try {
    $archiveOutput = [System.IO.Compression.ZipFile]::Open($stagedJar, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($sourceEntry in $archiveSource.Entries) {
            try {
                $entryBuffer = [System.IO.MemoryStream]::new()
                $sourceStream = $sourceEntry.Open()
                try {
                    $sourceStream.CopyTo($entryBuffer)
                } finally { $sourceStream.Dispose() }
                $entryBuffer.Position = 0
                $targetEntry = $archiveOutput.CreateEntry($sourceEntry.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
                $targetStream = $targetEntry.Open()
                try { $entryBuffer.CopyTo($targetStream) } finally { $targetStream.Dispose(); $entryBuffer.Dispose() }
            } catch {
                Write-Warning "Skipping unreadable jar entry $($sourceEntry.FullName): $($_.Exception.Message)"
            }
        }
    } finally { $archiveOutput.Dispose() }
} finally { $archiveSource.Dispose() }
if ($FallbackJar -and (Test-Path -LiteralPath $FallbackJar)) {
    $archiveOutput = [System.IO.Compression.ZipFile]::Open($stagedJar, [System.IO.Compression.ZipArchiveMode]::Update)
    $archiveFallback = [System.IO.Compression.ZipFile]::OpenRead($FallbackJar)
    try {
        foreach ($fallbackEntry in $archiveFallback.Entries) {
            if (!$archiveOutput.GetEntry($fallbackEntry.FullName)) {
                try {
                    $entryBuffer = [System.IO.MemoryStream]::new()
                    $sourceStream = $fallbackEntry.Open()
                    try {
                        $sourceStream.CopyTo($entryBuffer)
                    } finally { $sourceStream.Dispose() }
                    $entryBuffer.Position = 0
                    $targetEntry = $archiveOutput.CreateEntry($fallbackEntry.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
                    $targetStream = $targetEntry.Open()
                    try { $entryBuffer.CopyTo($targetStream) } finally { $targetStream.Dispose(); $entryBuffer.Dispose() }
                } catch { Write-Warning "Could not restore fallback jar entry $($fallbackEntry.FullName): $($_.Exception.Message)" }
            }
        }
    } finally { $archiveFallback.Dispose(); $archiveOutput.Dispose() }
}
$classFiles = @(
  "pvads/GaelNativeShot.class", "pvads/GaelNativeShot`$ShotOrigin.class", "pvads/GaelNativeShot`$WeaponPose.class", "pvads/GaelNativeShot`$ShotImpulse.class", "pvads/GaelNativeShot`$OriginScratch.class", "pvads/GaelNativeShot`$ShotAssist.class",
  "pvads/GaelBarrelRay.class", "pvads/GaelImpactMarker.class", "viewpointgael/AimProbe.class", "viewpointgael/Main.class",
  "viewpointgael/Patch_NativeShot.class", "viewpointgael/Patch_ShotOrigin.class", "viewpointgael/Patch_TBImpact.class", "viewpointgael/Patch_TBWorldImpact.class",
  "viewpointgael/Patch_TBDeflect.class", "viewpointgael/Patch_TBMuzzle.class", "viewpointgael/Patch_TBAimSolution.class", "viewpointgael/Patch_TBLaunch.class", "viewpointgael/Patch_TBProjectileGuide.class",
  "viewpointgael/Patch_AimClickFreeCursor.class",
  "viewpointgael/Patch_TBExpire.class", "viewpointgael/Patch_TBShot.class", "viewpointgael/Patch_ImpactCamera.class",
  "viewpointgael/Patch_ViewpointThirdPerson.class", "viewpointgael/Patch_ADSThirdPerson.class", "viewpointgael/Patch_ADSSlideNullModel.class", "viewpoint/input/ThirdPerson.class",
  "pvads/GaelWeaponMotion.class", "pvads/GaelWeaponMotion`$Fields.class", "pvads/GaelWeaponMotion`$Scratch.class", "pvads/GaelWeaponMotion`$Sample.class", "pvads/GaelWeaponMotion`$ReferenceAlignment.class",
  "viewpointgael/Patch_WeaponMotion.class", "viewpointgael/HoldSway.class", "viewpointgael/HoldSway`$Scratch.class", "viewpointgael/HoldSway`$State.class",
  "viewpointgael/Patch_HoldSway.class"
)
$jarTool = Join-Path (Split-Path $javacPath) 'jar.exe'
if (!(Test-Path -LiteralPath $jarTool)) { throw "JAR tool not found: $jarTool" }
$updateArgs = @('uf', $stagedJar)
foreach ($cf in $classFiles) {
  $sourceFile = Join-Path $buildRoot ($cf -replace "/", "\")
  if (Test-Path -LiteralPath $sourceFile) {
    $updateArgs += @('-C', $buildRoot, $cf)
  }
}
& $jarTool @updateArgs
if ($LASTEXITCODE -ne 0) { throw 'Could not update staged compatibility jar' }
if ($StageOnly) {
    if ($SkipVerification) { Write-Output "Staged jar (verification skipped): $stagedJar" }
    else { Write-Output "Verified staged jar: $stagedJar" }
    return
}
Assert-GameClosed
foreach ($buildVersion in @('42', '42.20')) {
    $destinationJar = Join-Path $PSScriptRoot "Contents\mods\ViewpointGaelCompat\$buildVersion\media\java\client\ViewpointGaelCompat.jar"
    Copy-Item -LiteralPath $stagedJar -Destination $destinationJar
    if ($DeployRoot) {
        $deployJar = Join-Path $DeployRoot "$buildVersion\media\java\client\ViewpointGaelCompat.jar"
        if (!(Test-Path -LiteralPath (Split-Path -Parent $deployJar))) {
            throw "Active mod deployment path not found for Build ${buildVersion}: $deployJar"
        }
        Copy-Item -LiteralPath $stagedJar -Destination $deployJar
    }
}
if ($SkipVerification) {
    Write-Output 'Native shot bridge compiled for 42 and 42.20 (verification skipped). Restart the game.'
} else {
    Write-Output 'Native shot bridge built and verified for 42 and 42.20. Restart the game.'
}
