package stgael.pz;

import java.util.List;
import java.util.LinkedHashMap;

import stgael.ballistics.BallisticEngine;
import stgael.ballistics.BallisticProfile;
import stgael.ballistics.BallisticVector3;
import pvads.GaelImpactMarker;
import zombie.GameTime;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.physics.BallisticsController;
import zombie.inventory.types.HandWeapon;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.core.random.Rand;

/** Main-thread bridge that advances Gael projectiles and resolves completed impacts. */
public final class PzBallisticRuntime {
    private static final double METRES_PER_TILE = 1.0;
    private static final double METRES_PER_LEVEL = 2.4494895935058594;
    private static final long OWNED_SHOT_HANDOFF_NS = 250_000_000L;
    private static final PzBallisticRuntime INSTANCE = new PzBallisticRuntime();

    private final PzBallisticCoordinates coordinates =
            new PzBallisticCoordinates(METRES_PER_TILE, METRES_PER_LEVEL);
    private final PzBallisticService service = new PzBallisticService(coordinates);
    private final PzProjectileLauncher launcher = new PzProjectileLauncher(service, coordinates);
    private final LinkedHashMap<Long, TrailView> diagnosticTrails = new LinkedHashMap<>();
    private volatile List<TrailView> publishedTrails = List.of();
    private static final ThreadLocal<ShotContext> ACTIVE_NATIVE_SHOT = new ThreadLocal<>();
    private static volatile boolean launchReported;
    private static volatile boolean duplicateSuppressionReported;

    private PzBallisticRuntime() {}

    /** Begin custom ownership for this one native firearm collision pass if configured. */
    public static void beginNativeShot(IsoGameCharacter shooter, HandWeapon weapon) {
        ACTIVE_NATIVE_SHOT.remove();
        if (GameClient.client || shooter == null || shooter != IsoPlayer.players[0]
                || weapon == null || !weapon.isAimedFirearm()
                || weapon.getProjectileCount() != 1 || !canFire(shooter, weapon)) return;
        BallisticProfile profile = PzBallisticProfileCatalog.forWeapon(weapon);
        BallisticsController controller = shooter.getBallisticsController();
        if (profile == null || controller == null) return;
        float min = weapon.getMinDamage();
        float max = weapon.getMaxDamage();
        if (!Float.isFinite(min) || !Float.isFinite(max) || min <= 0.0f || max < min) return;
        float baseDamage = min == max ? min : Rand.Next(min, max);
        ShotData data = new ShotData(
                new PzImpactDamageHandler.DamagePlan(baseDamage, 1.0f, false));
        ACTIVE_NATIVE_SHOT.set(new ShotContext(shooter, weapon, profile, data));
    }

    /** Mirror ISReloadWeaponAction.canShoot before a scoped projectile can be staged. */
    private static boolean canFire(IsoGameCharacter shooter, HandWeapon weapon) {
        if (weapon.isSelectFire() && "Safe".equals(weapon.getFireMode())) return false;
        if (shooter.isUnlimitedAmmo()) return true;
        if (weapon.isJammed()) return false;
        if (weapon.haveChamber()) return weapon.isRoundChambered();
        return weapon.getCurrentAmmoCount() > 0;
    }

    /** Launch after PZ's accepted-shot ammo event and BallisticsController update. */
    public static void launchStagedNativeShot(IsoGameCharacter shooter, HandWeapon weapon) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        if (context == null || context.launched || shooter != context.shooter
                || weapon != context.weapon || shooter == null) return;
        BallisticsController controller = shooter.getBallisticsController();
        if (controller != null && INSTANCE.launcher.launch(controller, weapon, shooter,
                context.profile, context.data.damagePlan, context.data)) {
            context.launched = true;
            context.launchedAt = System.nanoTime();
            context.data.markerSequence = GaelImpactMarker.sgtbShotStarted();
            if (!launchReported) {
                launchReported = true;
                System.out.println("[ViewpointGael] SGTB owns this shot: "
                        + weapon.getFullType() + " axis=" + context.profile);
            }
        }
    }

    /** Suppress only the immediate native character damage for a successfully launched shot. */
    public static boolean captureAndSuppressNativeHit(IsoGameCharacter target, HandWeapon weapon,
                                                       IsoGameCharacter attacker, float damage,
                                                       float rangeMultiplier) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        if (context == null || !context.firingTransactionActive || !context.launched
                || target == null || weapon != context.weapon
                || attacker != context.shooter || !Float.isFinite(damage)
                || !Float.isFinite(rangeMultiplier) || rangeMultiplier < 0.0f) return false;
        PzImpactDamageHandler.DamagePlan current = context.data.damagePlan;
        context.data.damagePlan = new PzImpactDamageHandler.DamagePlan(
                current.baseDamage(), rangeMultiplier, false);
        return true;
    }

    /** Capture PZ's weapon-level damage before its selected camera body-part modifiers. */
    public static boolean captureNativeDamageInputs(IsoGameCharacter target, HandWeapon weapon,
                                                     int bodyPart, float damageSplit) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        if (context == null || !context.firingTransactionActive || !context.launched
                || target == null || weapon != context.weapon
                || !Float.isFinite(damageSplit) || damageSplit <= 0.0f) return false;
        PzImpactDamageHandler.DamagePlan current = context.data.damagePlan;
        context.data.damagePlan = new PzImpactDamageHandler.DamagePlan(
                damageSplit, current.rangeMultiplier(), false);
        context.data.nativeTarget = target;
        return true;
    }

    /** Suppress firing-time reactions; the real projectile impact invokes them later. */
    public static boolean suppressNativeFiringReaction(IsoGameCharacter target,
                                                       IsoGameCharacter attacker,
                                                       HandWeapon weapon) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        return context != null && context.firingTransactionActive && context.launched
                && target != null && weapon == context.weapon
                && attacker == context.shooter;
    }

    /** Prevent PZ from dropping a helmet on the provisional camera target at trigger time. */
    public static boolean suppressNativeHelmetFall(IsoGameCharacter target) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        return context != null && context.firingTransactionActive && context.launched && target != null
                && target == context.data.nativeTarget;
    }

    public static void endNativeShot() {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        if (context == null) return;
        context.firingTransactionActive = false;
        if (!context.launched) ACTIVE_NATIVE_SHOT.remove();
        // Keep the successfully launched context briefly: other mods' exit
        // hooks can run before or after this one for the same PZ firing pass.
        // Its native-hit interception is closed; only the one-shot VTB handoff
        // token remains valid for the short window below.
    }

    /**
     * True Ballistics owns the shot only if SGTB did not successfully launch.
     * Its spawn hook asks this during the same PZ firing transaction.
     */
    public static boolean shouldSuppressTrueBallisticsSpawn(Object shooter, Object weapon,
                                                              boolean test) {
        ShotContext context = ACTIVE_NATIVE_SHOT.get();
        long sinceLaunch = context == null ? Long.MAX_VALUE
                : System.nanoTime() - context.launchedAt;
        boolean suppress = !test && context != null && context.launched
                && !context.duplicateSuppressed && sinceLaunch >= 0
                && sinceLaunch <= OWNED_SHOT_HANDOFF_NS
                && context.shooter == shooter && context.weapon == weapon;
        if (suppress) {
            // The compatibility handoff is for exactly one corresponding spawn.
            // Do not let a stale 250 ms token eat a later, unrelated shot.
            context.duplicateSuppressed = true;
            if (!duplicateSuppressionReported) {
                duplicateSuppressionReported = true;
                System.out.println("[ViewpointGael] SGTB suppressed the duplicate True Ballistics projectile.");
            }
        }
        return suppress;
    }

    /** Resolve a calibre profile from PZ's weapon script and launch if configured. */
    public static boolean launchConfigured(BallisticsController controller, HandWeapon weapon,
                                           IsoGameCharacter shooter,
                                           PzImpactDamageHandler.DamagePlan damagePlan) {
        BallisticProfile profile = PzBallisticProfileCatalog.forWeapon(weapon);
        if (profile == null) return false;
        return launch(controller, weapon, shooter, profile, damagePlan);
    }

    /** Entry point for a future post-fire hook; the caller supplies weapon/ammo policy. */
    public static boolean launch(BallisticsController controller, HandWeapon weapon,
                                 IsoGameCharacter shooter, BallisticProfile profile,
                                 PzImpactDamageHandler.DamagePlan damagePlan) {
        // Until projectile IDs are sent to and validated by the server, clients
        // must leave shot ownership with PZ's existing networked firearm path.
        if (GameClient.client || damagePlan == null) return false;
        return INSTANCE.launcher.launch(controller, weapon, shooter, profile, damagePlan,
                new ShotData(damagePlan));
    }

    /** Called once per game update from Lua. Simulation and damage stay on the PZ thread. */
    public static void updateFromGame() {
        IsoWorld world = IsoWorld.instance;
        GameTime gameTime = GameTime.getInstance();
        if (world == null || world.getCell() == null || gameTime == null) return;
        INSTANCE.update(world.getCell(), gameTime.getRealworldSecondsSinceLastUpdate());
    }

    private void update(IsoCell cell, double frameSeconds) {
        if (service.activeCount() == 0) {
            publishDiagnosticTrails(List.of());
            return;
        }
        List<BallisticEngine.Impact> impacts = service.update(cell, frameSeconds);
        publishDiagnosticTrails(impacts);
        for (BallisticEngine.Impact impact : impacts) {
            if (!(PzBallisticService.attachment(impact) instanceof ShotData shot)) continue;
            if (impact.projectile().owner() == IsoPlayer.players[0]) {
                String kind = switch (impact.collision().kind()) {
                    case CHARACTER -> "personaje";
                    case VEHICLE -> "vehículo";
                    case WINDOW -> "ventana";
                    case WORLD -> "mundo";
                };
                BallisticVector3 point = impact.collision().position();
                GaelImpactMarker.sgtbImpact(shot.markerSequence, point,
                        coordinates.metresPerTile(), kind);
            }
        }
    }

    private void publishDiagnosticTrails(List<BallisticEngine.Impact> impacts) {
        long now = System.nanoTime();
        IsoPlayer local = IsoPlayer.players[0];
        for (BallisticEngine.Impact impact : impacts) {
            var projectile = impact.projectile();
            if (projectile.owner() == local && local != null) {
                diagnosticTrails.put(projectile.id(), new TrailView(projectile.trailSnapshot(), now + 500_000_000L));
            }
        }
        for (var projectile : service.activeProjectilesSnapshot()) {
            if (projectile.owner() == local && local != null) {
                diagnosticTrails.put(projectile.id(), new TrailView(projectile.trailSnapshot(), now + 100_000_000L));
            }
        }
        diagnosticTrails.entrySet().removeIf(entry -> entry.getValue().expiresAt < now);
        while (diagnosticTrails.size() > 8) {
            Long oldest = diagnosticTrails.keySet().iterator().next();
            diagnosticTrails.remove(oldest);
        }
        publishedTrails = List.copyOf(diagnosticTrails.values());
    }

    public static int diagnosticTrailCount() { return INSTANCE.publishedTrails.size(); }

    /** Screen-space path encoded as x,y pairs separated by semicolons for the Lua overlay. */
    public static String diagnosticTrailPath(int trailIndex) {
        List<TrailView> trails = INSTANCE.publishedTrails;
        if (trailIndex < 0 || trailIndex >= trails.size()) return "";
        TrailView trail = trails.get(trailIndex);
        StringBuilder path = new StringBuilder();
        for (BallisticVector3 point : trail.points) {
            String screen = GaelImpactMarker.projectWorldPoint(point.x() / METRES_PER_TILE,
                    point.y() / METRES_PER_TILE, point.z());
            if (screen.isEmpty()) continue;
            if (path.length() > 0) path.append(';');
            path.append(screen);
        }
        return path.toString();
    }

    public static int activeProjectileCount() { return INSTANCE.service.activeCount(); }
    public static void clear() { INSTANCE.service.clear(); }

    private static final class ShotData {
        volatile PzImpactDamageHandler.DamagePlan damagePlan;
        volatile IsoGameCharacter nativeTarget;
        volatile long markerSequence = -1L;
        ShotData(PzImpactDamageHandler.DamagePlan damagePlan) {
            this.damagePlan = damagePlan;
        }
    }
    private static final class ShotContext {
        final IsoGameCharacter shooter;
        final HandWeapon weapon;
        final BallisticProfile profile;
        final ShotData data;
        boolean launched;
        boolean duplicateSuppressed;
        boolean firingTransactionActive = true;
        long launchedAt;

        ShotContext(IsoGameCharacter shooter, HandWeapon weapon,
                    BallisticProfile profile, ShotData data) {
            this.shooter = shooter;
            this.weapon = weapon;
            this.profile = profile;
            this.data = data;
        }
    }

    private record TrailView(List<BallisticVector3> points, long expiresAt) {}
}
