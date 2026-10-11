param(
    [Parameter(Mandatory = $true)][string]$CompilerJar,
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [Parameter(Mandatory = $true)][string]$AdsJar,
    [Parameter(Mandatory = $true)][string]$ViewpointJar,
    [switch]$StageOnly,
    [string]$JavaExe
)
$ErrorActionPreference = 'Stop'
foreach ($requiredPath in @($CompilerJar, $GameRoot, $AdsJar, $ViewpointJar)) {
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
$baseJar = Join-Path $PSScriptRoot 'Contents\mods\ViewpointGaelCompat\42\media\java\client\ViewpointGaelCompat.jar'
$apiJars = @((Join-Path $GameRoot 'projectzomboid.jar'), (Join-Path $GameRoot 'ZombieBuddy.jar'), $AdsJar, $ViewpointJar, $baseJar)
foreach ($apiJar in $apiJars) {
    if (!(Test-Path -LiteralPath $apiJar)) { throw "Required API jar not found: $apiJar" }
}
$classPath = $apiJars -join ';'
$sources = @('src\pvads\GaelNativeShot.java', 'src\pvads\GaelWeaponMotion.java', 'src\pvads\GaelImpactMarker.java', 'src\viewpointgael\Patch_WeaponMotion.java', 'src\viewpointgael\HoldSway.java', 'src\viewpointgael\Patch_HoldSway.java', 'src\viewpointgael\Patch_ShotOrigin.java', 'src\pvads\GaelBarrelRay.java', 'src\viewpointgael\AimProbe.java', 'src\viewpointgael\Patch_NativeShot.java', 'src\viewpointgael\Patch_TBImpact.java', 'src\viewpointgael\Patch_TBWorldImpact.java', 'src\viewpointgael\Patch_TBExpire.java', 'src\viewpointgael\Patch_TBShot.java', 'src\viewpointgael\Patch_ImpactCamera.java', 'tests\GaelNativeShotTest.java', 'tests\GaelMirroredShotTest.java', 'tests\GaelLuaRecoilTest.java', 'tests\GaelPhysicalAxisTest.java', 'tests\GaelWeaponPivotTest.java') | ForEach-Object { Join-Path $PSScriptRoot $_ }
& $javaPath -jar $CompilerJar -25 -proc:none -classpath $classPath -d $buildRoot @sources
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }
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
# Update only these classes; the existing jar includes additional patches
# whose source is not yet in this repository. Never rebuild it from src alone.
$stagedJar = Join-Path $buildRoot 'ViewpointGaelCompat.jar'
Copy-Item -LiteralPath $baseJar -Destination $stagedJar
& jar uf $stagedJar -C $buildRoot pvads/GaelNativeShot.class -C $buildRoot 'pvads/GaelNativeShot$ShotOrigin.class' -C $buildRoot 'pvads/GaelNativeShot$WeaponPose.class' -C $buildRoot 'pvads/GaelNativeShot$OriginScratch.class' -C $buildRoot pvads/GaelBarrelRay.class -C $buildRoot pvads/GaelImpactMarker.class -C $buildRoot viewpointgael/AimProbe.class -C $buildRoot viewpointgael/Patch_NativeShot.class -C $buildRoot viewpointgael/Patch_ShotOrigin.class -C $buildRoot viewpointgael/Patch_TBImpact.class -C $buildRoot viewpointgael/Patch_TBWorldImpact.class -C $buildRoot viewpointgael/Patch_TBExpire.class -C $buildRoot viewpointgael/Patch_TBShot.class -C $buildRoot viewpointgael/Patch_ImpactCamera.class -C $buildRoot pvads/GaelWeaponMotion.class -C $buildRoot 'pvads/GaelWeaponMotion$Fields.class' -C $buildRoot 'pvads/GaelWeaponMotion$Scratch.class' -C $buildRoot 'pvads/GaelWeaponMotion$Sample.class' -C $buildRoot viewpointgael/Patch_WeaponMotion.class -C $buildRoot viewpointgael/HoldSway.class -C $buildRoot 'viewpointgael/HoldSway$Scratch.class' -C $buildRoot 'viewpointgael/HoldSway$State.class' -C $buildRoot viewpointgael/Patch_HoldSway.class
if ($LASTEXITCODE -ne 0) { throw 'Jar update failed' }
if ($StageOnly) {
    Write-Output "Verified staged jar: $stagedJar"
    return
}
Assert-GameClosed
foreach ($buildVersion in @('42', '42.20')) {
    $destinationJar = Join-Path $PSScriptRoot "Contents\mods\ViewpointGaelCompat\$buildVersion\media\java\client\ViewpointGaelCompat.jar"
    Copy-Item -LiteralPath $stagedJar -Destination $destinationJar
}
Write-Output 'Native shot bridge built and verified for 42 and 42.20. Restart the game.'
