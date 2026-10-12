# STableGaelTrueBallistics: independent implementation

This document describes a new implementation. No source files, algorithms, or
compiled classes from Viewpoint True Ballistics are included here.

## Capability comparison with installed Viewpoint True Ballistics 1.3.2

This is a feature audit of the locally installed VTB 1.3.2 source, not a code
port. SGTB currently has roughly 25–35% of its functional breadth. Its independent
flight core and single-player firing-to-impact path exist, but that path still
needs gameplay verification and the feature coverage below remains incomplete.

| Capability | SGTB now | Remaining for comparable coverage |
|---|---|---|
| Flight physics | Own bounded midpoint integrator with gravity and linear drag; weapon-axis launch | Calibrate drag/velocity units and profiles; add ballistic zero, shot dispersion and pellet spread |
| Profiles | Seven ammo categories, one default profile per category | Broader ammo-name resolution, unknown-ammo fallback, weapon/ammo overrides and per-load tuning |
| Collision | Static blocked-square query; approximate character cylinder; native vehicle segment intersection; nearest hit wins | Doors/windows as distinct penetrable contacts, furniture detail, vehicle impact-part precision, skeleton/body capsules and penetration through bodies/surfaces |
| Damage | Defers the local native hit; applies PZ character damage and calls PZ vehicle-part damage at the simulated impact | Exact character hit zones including hands/feet, impact-directed vehicle part selection, ammo-specific falloff/critical/armor parity and complete native side-effect audit |
| Shotgun/NPC | Not owned; native fallback | Multiple independently simulated pellets with spread; separate authoritative launch source for NPCs |
| Multiplayer | Explicitly leaves PZ's native network shot path in control | Client request, server validation/ownership, projectile or impact replication, and safe handling of PZ's existing hit packets |
| Diagnostics | Optional local path trail and impact marker | Comparable per-shot profile/flight/collision diagnostics and performance counters |

One architectural distinction matters: VTB's multiplayer flow simulates the shot
on the firing client and lets the server validate the resulting native hit
packets; it does not fully re-simulate each flight on the server. The SGTB plan
currently aims for server-owned flight and damage, which is stronger authority
but requires more integration work. The estimate above is feature breadth, not a
prediction of implementation time.

## Ownership and current verification state

This source is a new implementation, not a port. The existing Viewpoint True
Ballistics patches remain a separate compatibility path for shots SGTB cannot
successfully launch. SGTB can own an aimed single-projectile shot in single-player
even when True Ballistics is loaded: after SGTB confirms its launch, a narrow
adapter suppresses only True Ballistics' duplicate `spawnShot` for the same shooter
and weapon immediately after the firing transaction, consuming that one-shot handoff token
after the first matching spawn. Native hit/damage/reaction interception is active
only during `CombatManager.attackCollisionCheck`; the short-lived handoff context
cannot intercept a later SGTB impact. The latest Build 42 game log confirms an SGTB-owned
`Base.M9_Samurai` shot and the matching duplicate suppression. Collision impact
and damage behavior still need in-game validation. The server-authority path is
not implemented.

## Initial physics core

`src/stgael/ballistics` contains a game-independent core:

- `BallisticVector3` stores world-space positions and directions.
- `BallisticProfile` carries muzzle speed, gravity, drag, range, and lifetime.
- `BallisticProjectile` launches from a supplied muzzle position along a supplied
  barrel direction and advances with bounded midpoint integration.

The PZ-facing adapter translates the current calibrated ADS barrel axis into this
core's world-space vector, including post-ADS sway and short-lived visible shot
carry. A world-query adapter checks each swept segment against
loaded world geometry and characters before committing the next step.

The first PZ adapters now live in `src/stgael/pz`: `PzBallisticCoordinates`
converts native tile/level coordinates, and `PzWorldCollisionResolver` queries
`LosUtil.getFirstBlockingIsoGridSquare` for a blocked swept segment. The horizontal
scale is an explicit constructor input (the initial nominal value is one metre per
tile); it must be calibrated against gameplay before we choose projectile speeds.
PZ returns a collision-data object for clear rays too, so the adapter checks its
`testResults` for `Blocked` before stopping a projectile. If PZ omits `hitPosition`,
the resolver intersects the swept segment with the blocking square's bounds instead
of approximating impact at the square center.

`PzBallisticRuntime` owns the engine, launcher, collision resolver, and damage
handler on the game thread. `Patch_GaelBallisticRuntime` advances it after each
`GameTime.update`. `Patch_GaelBallisticFiring` opens a scoped context around
`CombatManager.attackCollisionCheck`, after mirroring PZ's safe-mode, jammed,
chamber, and ammo checks (including unlimited-ammo mode). The projectile launch is
staged and runs at the beginning of PZ's `fireWeapon`, after the
`OnWeaponSwingHitPoint` ammo event and `BallisticsController.update`. Only after that launch succeeds does the
context defer PZ's provisional character reaction, body-part/armor calculation,
helmet loss, and immediate `Hit` until the projectile's actual impact. Each
projectile retains its weapon and damage plan at launch.

The runtime rejects launches on a multiplayer client until projectile IDs and
server-side validation exist. PZ's native networked shot path remains authoritative
in multiplayer; the independent server simulation and client replication are still
required milestones. When SGTB successfully launches in single-player, its firing
context also suppresses the corresponding loaded True Ballistics `spawnShot`, so
one trigger pull cannot create both independent and VTB projectiles.

`PzCharacterCollisionResolver` now scans nearby squares for shootable characters
and tests each segment against a configurable body-cylinder approximation. A
projectile also carries its shooter identity to prevent self-collision.
`PzVehicleCollisionResolver` also sweeps segments against loaded vehicles through
PZ's `BaseVehicle.getIntersectPoint` API, with a conservative horizontal broad
phase. `PzCollisionResolver` compares character, vehicle, and world contacts and
returns the nearest, allowing a wall or vehicle to stop a round before it reaches
a character. Vehicle contacts are routed through `BaseVehicle.processHit`; which
vehicle part receives the hit remains controlled by Project Zomboid. The character
shape is an initial approximation and needs in-game calibration.

Successful local SGTB launches now start a separate impact-marker sequence, and
terminal world/character contacts publish their exact simulated contact point to
the existing HUD projection. The firing adapter is restricted to the local player
because its current physical-axis bridge samples that player's rendered weapon;
NPC launch directions need a separate authoritative source before enabling them.
For calibration, each local projectile retains a bounded recent position trail;
the optional `SGTBDebugTrajectory` sandbox setting draws those samples through the
same captured Viewpoint camera projection. This visual is diagnostic only and does
not control projectile flight or collision.

`PzImpactDamageHandler` derives an approximate ragdoll body region from the
projectile's actual contact height, briefly injects that region into the firing
player's current and cached camera-target rows, then calls
`CombatManager.processHit` so PZ produces its corresponding hit reaction. It
restores those shared rows immediately afterward, applies PZ's private
`applyRangeHitLocationDamage` to the same region, and calls
`IsoGameCharacter.Hit`. Firing-time patches capture the pre-location damage input
and defer those operations for an SGTB-owned shot. When the native ray found no
character, the launcher retains a random weapon min/max damage fallback. This path
compiles but still needs in-game checks of target reaction, armor, damage, helmet
loss, and side effects. The handler rejects a network client; projectile requests
are not yet sent to or validated by a server.

## PZ integration findings

- `CombatManager.attackCollisionCheck(IsoGameCharacter, HandWeapon,
  SwipeStatePlayer, AttackType)` owns the built-in character damage pass (public
  in the installed Build 42 JAR). It triggers the shot event,
  calculates `HitInfo` targets, updates the ballistics controller, and later calls
  `processHit` and `IsoMovingObject.Hit` for accepted targets. Its surrounding code
  also handles muzzle flash, shot statistics, endurance, muscle strain, last-hit
  count, and network client notification. A replacement must preserve those
  side-effects while replacing the target/damage pass exactly once.
- `CombatManager.fireWeapon(HandWeapon, IsoGameCharacter)` is a private tracer and
  obstruction-effect helper called from `attackCollisionCheck`; it does not apply
  character damage. Hooking or skipping it alone would leave native character hit
  resolution untouched and would not hand ownership to the new engine.
- `IsoGameCharacter.getBallisticsController()` supplies the firing character's
  current controller, and `BallisticsController.calculateMuzzlePosition(Vector3,
  Vector3)` supplies the game-calibrated muzzle position and baseline direction.
  `GaelNativeShot.currentPhysicalShotDirection(String, Vector3)` exposes a fresh
  ADS barrel axis without referencing VTB classes. SGTB can use this same axis
  while VTB is loaded; a scoped firing hook suppresses VTB's duplicate only after
  SGTB has successfully launched the single-player shot.
- `LosUtil.getFirstBlockingIsoGridSquare(...)` returns a blocking square and a
  `hitPosition`, which is a candidate for world obstruction queries. Its integer
  endpoints make it unsuitable as the only collision method for moving targets.
- `CombatManager.processHit(...)` is not a general impact API: its body-part choice
  comes from the camera-target cache, and its direction is recomputed from shooter
  and target. SGTB scopes a temporary cache override to the impact reaction,
  restoring both arrays and their counts in a `finally` block. The selected body
  region remains an approximation from contact height, rather than PZ's exact
  ragdoll contact geometry.
- Build 42 exposes `BodyPartType.FromIndex`, `BodyPartType.ToIndex`, and
  `BodyDamage.getBodyPart(BodyPartType)` for mapping an impact-derived region to
  the body's damage model. `CombatManager.processHit` returns a separate integer
  reaction index, while `RagdollBodyPart.getBodyPartType(int)` provides a mapping
  API between its physics regions and damage-body indices. Impact-height regions
  still need in-game calibration against PZ's hit reactions and damage model.
- Build 42 `HitInfo` has a public `init(IsoMovingObject, x, y, z, dot, distSq)`
  method. However, `setBallisticsCameraTargetHitLocation(index, HitInfo)` copies
  coordinates from PZ's existing camera-target cache into the supplied object; it
  does not accept a projectile contact or update the cached body-part selection.
  SGTB temporarily overrides the cache fields for the synchronous call to
  `processHit`, then restores them immediately.
- `IsoGameCharacter.Hit(HandWeapon, IsoGameCharacter, float, boolean, float)` applies
  PZ's own damage calculation and hit consequences; its float inputs must still be
  derived from the actual ammo and range policy. Calling `processHit` afterward gives
  a reaction but does not select the projectile's true body part automatically.

The single-player firing adapter now intercepts the immediate hit only after SGTB
successfully creates a projectile. The scoped context limits reaction and damage
deferrals to the selected shooter and weapon. Remaining hit side-effects and body
part fidelity still need an in-game audit.

## Multiplayer protocol plan

The current firing owner explicitly declines `GameClient.client`; multiplayer
therefore remains on PZ's native path. Do not remove that guard until the server
owns projectile creation, collision, and damage. Build 42 exposes
`GameClient.sendClientCommand(...)` / Lua `sendClientCommand(...)` for client to
server requests and `GameServer.sendServerCommand(...)` for server to client
replication ([GameClient API](https://projectzomboid.com/modding/zombie/network/GameClient.html),
[GameServer API](https://projectzomboid.com/modding/zombie/network/GameServer.html),
[Lua global API](https://projectzomboid.com/modding/zombie/Lua/LuaManager.GlobalObject.html)).
The installed game's server Lua also registers handlers with
`Events.OnClientCommand.Add(...)` in `media/lua/server/ClientCommands.lua`.

The intended flow is:

1. The firing client sends only a monotonically increasing per-player shot
   sequence, requested weapon full type, ammo script key, and a normalized
   physical-barrel direction. It never sends damage, target identity, body part,
   collision point, muzzle position, or a projectile velocity that the server
   will accept as authoritative.
2. A server `OnClientCommand` handler obtains the shooter from the event's
   connection-bound player argument, then validates the equipped weapon, loaded
   ammo, single-projectile policy, firing interval, sequence freshness, and
   server-side range/profile. It derives the muzzle and baseline direction from
   that character's [`BallisticsController.calculateMuzzlePosition(...)`](https://albion.codeberg.page/PZ-JavaDocs/zombie/core/physics/BallisticsController.html);
   PZ also exposes [`IsoPlayer.getAimVector(Vector2)`](https://albion.codeberg.page/PZ-JavaDocs/zombie/characters/IsoPlayer.html)
   as a candidate horizontal aim basis.
   The requested barrel direction must be normalized and remain within a bounded
   3D angle of the server-derived baseline, with its horizontal projection checked
   against the server-side aim vector. Whether `getAimVector` is fresh enough at
   `OnClientCommand` time still needs runtime verification; if it is stale, use
   the controller baseline alone and reject large client corrections.
3. Accepted requests launch the shared `stgael.ballistics` engine on the server
   main thread. Only that simulation resolves loaded-world and character
   collisions and calls PZ's impact damage pipeline. Duplicate or stale sequence
   numbers are rejected before ammo or projectile state changes.
4. The server replicates accepted projectile visuals and resolved impacts to
   relevant clients using `sendServerCommand`; clients render those messages and
   never create a second damage-owning projectile.
5. The game-independent engine/profile classes and `PzBallisticService` are now
   separated from the client runtime. The service takes validated world
   coordinates and a PZ character/weapon, advances projectiles through shared
   world/character collision and impact-damage code, and does not load the HUD
   marker or ADS bridge. A server companion can compile that service and its
   PZ-facing collision/damage dependencies. `PzProjectileLauncher` remains
   client-side because it reads the local ADS pose; a server launcher must consume
   validated request data and server-derived muzzle coordinates.

The installed Build 42 `CombatManager.attackCollisionCheck` source adds an
important packet-order constraint: the client first triggers the swing/ammo event
and sends `GameClient.sendAttackCollisionCheck(player, weapon, hitCount)`, then
builds provisional hit lists and sends each through `GameClient.sendPlayerHit`.
A multiplayer replacement must trace and preserve the server-side handling of
both packets before it suppresses either one. Sending a custom ballistic request
while allowing `sendPlayerHit` would double-apply damage; suppressing only
`sendPlayerHit` without preserving the attack/ammo event could lose native firing
side effects. This is why the current multiplayer client guard remains enabled.

This is a protocol design, not an implemented multiplayer path. Direction
validation against PZ's server-side aim state and ammo/fire-rate authority are
explicit prerequisites; until they are implemented, the current client guard
and PZ native multiplayer shot path must remain in place.

There is also a packaging gate before server code can run: this mod's `mod.info`
currently points `javaJarFile` at `media/java/client/ViewpointGaelCompat.jar`.
ZombieBuddy skips that path on dedicated servers. ZombieBuddy's [official modding
guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/ModdingGuide.md)
documents that 2.x reads only one unsuffixed JAR path per mod and skips
`media/java/server/` JARs on clients. The server work therefore needs a separate
server companion mod with its own `javaPkgName` and server-only JAR, plus a Lua
`OnClientCommand` receiver. The main client mod sends a bounded shot request and
renders only server-approved projectile updates. The engine core, profile catalog,
`PzBallisticService`, collision resolvers, and impact handler can be compiled into
that server JAR from the same sources, so no client-only classes or duplicated
physics implementation are needed. Merely adding a Lua receiver to this
client-only JAR would not provide server authority.

The installed JAR also confirms `HandWeapon` exposes native `getMinDamage`,
`getMaxDamage`, `getMaxRange`, `getProjectileCount`, and `getAmmoPerShoot`. These
do not identify the loaded ammo's impact policy. The current adapter captures PZ's
raw single-projectile damage input and applies PZ's body-part/armor method at
impact; per-ammo values and runtime results still need validation. It must not infer bullet velocity from weapon
`getBaseSpeed`, which is a firing-cycle property.

`PzBallisticProfileCatalog` now resolves a profile by the weapon script's PZ
`AmmoType` item key. It includes nominal starting velocities for 9 mm, .38, .357,
.44, .45, .308, and 5.56 categories, and allows Lua/other mods to override any
profile through `AimProbe.registerBallisticProfile`. PZ's built-in scripts expose
ammo categories but no projectile muzzle velocity; the stock values are therefore
manufacturer-load starting points, with one profile per calibre rather than exact
per-load data. The seed values were converted from Federal catalog / load data for
9 mm and .38, 5.56, .357/.44/.45, and .308 respectively:
[Federal handgun/rifle catalog](https://www.federalpremium.com/on/demandware.static/-/Library-Sites-VistaFederalSharedLibrary/default/vd892add607ae553a1525961c7d97d49eec4ac9bb/productPdfFiles/Catalog/FP2158_2026-Federal-Catalog_WEB.pdf),
[Federal handgun catalog](https://www.federalpremium.com/on/demandware.static/-/Library-Sites-VistaFederalSharedLibrary/default/vd5051f299f79146229507233809e6144584db865/contentDocuments/catalog/Federal_Catalog_2021_single.pdf),
[Federal .308 load data](https://reloadingdata.federalpremium.com/downloads/speer/reloading-pdfs/rifle/308_Winchester_150.pdf).
A firing adapter can fall back to the native path when the category
has no profile, including shotgun shells until pellet spread/count is integrated.

The single-player firing adapter wraps PZ's `CombatManager.attackCollisionCheck`.
When the weapon is an aimed firearm with one projectile, a calibre profile exists,
and the Gael physical barrel direction is fresh, it launches one SGTB projectile
even if True Ballistics is loaded. Only after a successful launch do scoped
patches defer `processHit`, `applyRangeHitLocationDamage`, helmet loss, and PZ's
immediate `Hit`; the actual impact runs these operations later. Missing profile,
stale pose, or multiplayer client leaves PZ's original hit path unchanged.
Shotgun pellets, exact body-part contact, and multiplayer authority
remain open milestones.

For the existing VTB compatibility correction, consecutive-shot angular carry is
mirrored into `HoldSway` as a short-lived arm/weapon bone rotation. The delta used
for the next carry is measured from the physical barrel ray with the previous carry
overlay excluded, preventing visual carry from feeding itself into larger and
larger ballistic corrections. The final VTB shot correction is not clamped to the
ordinary 25-degree sway limit: that limit previously let the projectile keep
correcting after the visible weapon had stopped. The visual carry fades over 300 ms.
SGTB takes a different path: its launcher reads the current rendered barrel axis
directly, including visible ADS sway and carry, so it does not add a separate
reticle-centering correction that could make its trajectory diverge from the model.

`IsoGameCharacter.Hit` has both five- and six-argument overloads in this Build 42
JAR. Any adapter should call the overload and companion reaction code used by the
actual native firearm path, rather than assuming the existing five-argument helper
fully reproduces it.

The PZ collision adapter detects static map obstruction and approximated character
bodies. It does not yet resolve vehicles/windows or determine exact body-part contact.
The single-player firing-to-impact path is connected in source but not yet verified
in gameplay. Per-ammo damage calibration, multiplayer authority, and deterministic
server-side simulation remain unimplemented.

## Required integration milestones

1. Verify in game that interception occurs after PZ accepts a fired round and
   preserves ammo, chamber, jam, sound, and recoil behavior.
2. Calibrate the single-projectile launch, then add per-pellet launch and spread
   before extending the adapter to shotguns.
3. Calibrate swept world/character collisions, including floors, windows, vehicles,
   and exact body-part contact.
4. Compare PZ damage, armor, critical, helmet, and hit side-effects against native
   shots for supported ammo types.
5. Implement the server request/validation/replication flow above before enabling
   SGTB in multiplayer or removing the VTB dependency.

The new mod must not be enabled alongside another firearm hit-detection owner.
