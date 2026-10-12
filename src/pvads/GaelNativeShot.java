package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.inventory.types.HandWeapon;
import zombie.iso.Vector3;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import java.lang.reflect.Field;
import viewpointgael.HoldSway;

/** Shares the calibrated ADS shot direction with Build 42's native ballistics. */
public final class GaelNativeShot {
    private static final double FLOOR_HEIGHT = 2.4494895935058594;
    private static final ThreadLocal<Vector3f> SHOT_DIRECTION = ThreadLocal.withInitial(Vector3f::new);
    private static final ThreadLocal<Vector3f> SHOT_BASE_DIRECTION = ThreadLocal.withInitial(Vector3f::new);
    private static final ThreadLocal<OriginScratch> ORIGIN_SCRATCH = ThreadLocal.withInitial(OriginScratch::new);
    private static volatile ShotOrigin shotOrigin;
    private static volatile WeaponPose weaponPose;
    private static boolean announced;
    private static boolean originAnnounced;
    private static boolean trueBallisticsAnnounced;
    private static volatile double shotMotionGain = 0.35;
    private static volatile double shotCentering;
    private static volatile boolean shotCenteringActive;
    private static String previousShotWeapon;
    private static long previousShotAt;
    private static double previousShotYaw, previousShotPitch;
    private static String previousCenteringWeapon;
    private static long previousCenteringShotAt;
    private static int centeringBurstShotCount;
    private static final long SHOT_MOTION_WINDOW_NANOS = 300_000_000L;
    private static final long CENTERING_BURST_WINDOW_NANOS = 1_000_000_000L;
    private static final double MAX_SHOT_MOTION_DELTA = Math.toRadians(2.0);

    /** Model-space offsets from the weapon's normal muzzle point; units are the weapon mesh's units. */
    public static boolean setShotOrigin(String weapon, double x, double y, double z) {
        if (weapon == null || !Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z)) return false;
        shotOrigin = new ShotOrigin(weapon, clamp(x), clamp(y), clamp(z), System.nanoTime());
        return true;
    }

    private static float clamp(double value) { return (float) Math.max(-2.0, Math.min(2.0, value)); }

    /** Additional share of the measured angular change from the previous shot. */
    public static void setShotMotionGain(double gain) {
        if (Double.isFinite(gain)) shotMotionGain = Math.max(0.0, Math.min(2.0, gain));
    }

    /** Blend the projectile's physical barrel axis toward the camera-center aim ray. */
    public static void setShotCentering(double amount, boolean aiming) {
        shotCenteringActive = aiming;
        if (!aiming) {
            shotCentering = 0.0;
            previousCenteringWeapon = null;
            previousCenteringShotAt = 0L;
            centeringBurstShotCount = 0;
            return;
        }
        if (Double.isFinite(amount)) shotCentering = Math.max(0.0, Math.min(1.0, amount));
    }

    /** Immutable render-thread snapshot consumed by the firing thread. */
    public static void publishWeaponPose(Matrix4f pose, String weapon, float angle) {
        if (pose == null || weapon == null || !Float.isFinite(angle)) return;
        weaponPose = new WeaponPose(weapon, new Matrix4f(pose), angle, System.nanoTime());
    }

    /**
     * Read the most recent physical ADS barrel axis for a parallel projectile
     * implementation. This method has no True Ballistics dependency and only
     * succeeds while the render pose is fresh and belongs to the requested gun.
     * The output uses PZ ballistics axes, with vertical expressed in tile levels.
     */
    public static boolean currentPhysicalShotDirection(String weaponId, Vector3 out) {
        if (weaponId == null || out == null || !GaelWeaponMotion.ready()) return false;
        WeaponPose pose = weaponPose;
        if (pose == null || !weaponId.equals(pose.weaponId)
                || System.nanoTime() - pose.at > 150_000_000L) return false;
        Vector3f barrel = SHOT_DIRECTION.get();
        return GaelWeaponMotion.shotDirection(pose.angle, barrel)
                && writePhysicalDirection(out, barrel.x, barrel.y, barrel.z);
    }

    public static void afterPresence(Object controller, Object direction) {
        IsoPlayer player = IsoPlayer.players[0];
        if (!(direction instanceof Vector3) || player == null || !GaelWeaponMotion.ready()
                || player.getBallisticsController() != controller || !player.isAiming()
                || !(player.getPrimaryHandItem() instanceof HandWeapon weapon)
                || !weapon.isAimedFirearm() || !VP.firstPerson() || VP.freeCam()) {
            return;
        }
        // Fire along the physical weapon axis, including the visible Pitch/Yaw recoil.
        // Keep the ADS sight ray for previews/impact markers, but don't substitute it
        // for the barrel direction: that made the gun move while bullets stayed centered.
        WeaponPose pose = weaponPose;
        if (pose == null || System.nanoTime() - pose.at > 150_000_000L
                || !pose.weaponId.equals(weapon.getFullType())) return;
        Vector3f barrel = SHOT_DIRECTION.get();
        if (!GaelWeaponMotion.shotDirection(pose.angle, barrel)
                || !writePhysicalDirection((Vector3) direction, barrel.x, barrel.y, barrel.z)) return;
        if (!announced) {
            announced = true;
            System.out.println("[ViewpointGael] Native ballistics now follows the physical ADS weapon axis");
        }
    }

    /** Runs after Project Viewpoint's LeanShot callback, so this remains the final muzzle offset. */
    public static void afterLean(Object controller, Object muzzle) {
        IsoPlayer player = IsoPlayer.players[0];
        ShotOrigin offset = shotOrigin;
        WeaponPose pose = weaponPose;
        if (!(muzzle instanceof Vector3 start) || player == null || offset == null
                || System.nanoTime() - offset.at > 500_000_000L
                || pose == null || System.nanoTime() - pose.at > 500_000_000L
                || player.getBallisticsController() != controller || !player.isAiming()
                || !(player.getPrimaryHandItem() instanceof HandWeapon weapon)
                || !weapon.isAimedFirearm() || !VP.firstPerson() || VP.freeCam()
                || !offset.weaponId.equals(weapon.getFullType()) || !pose.weaponId.equals(weapon.getFullType())
                || (offset.x == 0f && offset.y == 0f && offset.z == 0f)) return;
        try {
            OriginScratch work = ORIGIN_SCRATCH.get();
            pose.model.transformDirection(work.modelOffset.set(offset.x, offset.y, offset.z));
            work.worldOffset.set(work.modelOffset.x, work.modelOffset.y, work.modelOffset.z);
            Model.vectorToWorldCoords(0f, 0f, 0f, pose.angle, work.worldOffset);
            if (!Float.isFinite(work.worldOffset.x) || !Float.isFinite(work.worldOffset.y)
                    || !Float.isFinite(work.worldOffset.z)) return;
            start.x += work.worldOffset.x;
            start.y += work.worldOffset.y;
            start.z += work.worldOffset.z;
            if (!originAnnounced) {
                originAnnounced = true;
                System.out.println("[ViewpointGael] calibrated shot origin applied in weapon model space");
            }
        } catch (Throwable error) {
            System.err.println("[ViewpointGael] calibrated shot origin unavailable: " + error);
        }
    }

    static boolean writeDirection(Vector3 direction, double[] ray) {
        if (ray == null || ray.length < 6) return false;
        return writeDirection(direction, ray[3], ray[4], ray[5]);
    }

    /** Force the projectile objects True Ballistics already created to use the live ADS pose. */
    public static boolean correctTrueBallisticsShot(Object manager, Object group) {
        IsoPlayer player = IsoPlayer.players[0];
        WeaponPose pose = weaponPose;
        if (manager == null || group == null || player == null || !player.isAiming()
                || !(player.getPrimaryHandItem() instanceof HandWeapon weapon)
                || !weapon.isAimedFirearm() || !VP.firstPerson() || VP.freeCam()
                || !GaelWeaponMotion.ready() || pose == null
                || System.nanoTime() - pose.at > 150_000_000L
                || !pose.weaponId.equals(weapon.getFullType())) return false;
        Vector3f rendered = SHOT_DIRECTION.get();
        if (!GaelWeaponMotion.shotDirection(pose.angle, rendered)) return false;
        // True Ballistics V3 uses tile X/Y and meters-up U. ADS render axes are
        // (-worldX, up, -worldY), the same mapping as the native shot bridge.
        double x = -rendered.x, y = -rendered.z, u = rendered.y;
        double length = Math.sqrt(x*x + y*y + u*u);
        if (!Double.isFinite(length) || length < 1e-6) return false;
        x /= length; y /= length; u /= length;
        Vector3f baseRendered = SHOT_BASE_DIRECTION.get();
        if (!GaelWeaponMotion.shotDirection(pose.angle, baseRendered, true, false)) return false;
        double baseX = -baseRendered.x, baseY = -baseRendered.z, baseU = baseRendered.y;
        double baseLength = Math.sqrt(baseX * baseX + baseY * baseY + baseU * baseU);
        if (!Double.isFinite(baseLength) || baseLength < 1e-6) return false;
        baseX /= baseLength; baseY /= baseLength; baseU /= baseLength;
        // This is the rendered weapon axis without the temporary per-shot carry.
        // The final projectile ray may receive additional aim-centering and burst
        // corrections below; mirror their combined angular offset onto the model.
        double visualBaseYaw = Math.atan2(baseY, baseX);
        double visualBasePitch = Math.atan2(baseU, Math.hypot(baseX, baseY));
        double physicalX = x, physicalY = y, physicalU = u;
        long shotAt = System.nanoTime();
        boolean sameBurst = weapon.getFullType().equals(previousShotWeapon)
                && shotAt > previousShotAt && shotAt - previousShotAt <= SHOT_MOTION_WINDOW_NANOS;
        boolean sameCenteringBurst = shotCenteringActive
                && weapon.getFullType().equals(previousCenteringWeapon)
                && shotAt > previousCenteringShotAt
                && shotAt - previousCenteringShotAt <= CENTERING_BURST_WINDOW_NANOS;
        int centeringShotIndex = sameCenteringBurst ? centeringBurstShotCount + 1 : 1;
        double centering = shotCenteringActive
                ? shotCentering * centeringBurstEffect(centeringShotIndex) : 0.0;
        // Short gameplay aim assist: after a full ADS ramp, the first three
        // shots snap to the camera-center ray in ideal conditions, overriding
        // the weapon's physical barrel direction. Condition penalties apply.
        if (shotCenteringActive && centeringShotIndex <= 3 && shotCentering >= 0.99) {
            centering = 1.0;
        }
        if (centering > 0) {
            // Aim-centering previously replaced the already-swung barrel ray,
            // making the rendered HoldSway disappear from ideal first shots.
            // Correct the base ADS ray toward the reticle, then preserve the
            // actual post-ADS weapon sway as an angular offset on top of it.
            Vector3f baseDirection = SHOT_BASE_DIRECTION.get();
            if (!GaelWeaponMotion.shotDirection(pose.angle, baseDirection, false)) return false;
            double centerBaseX = -baseDirection.x, centerBaseY = -baseDirection.z, centerBaseU = baseDirection.y;
            double swayX = x - centerBaseX, swayY = y - centerBaseY, swayU = u - centerBaseU;
            double yawToCenter = VP.yaw(), pitchToCenter = VP.pitch();
            if (Double.isFinite(yawToCenter) && Double.isFinite(pitchToCenter)) {
                double horizontal = Math.cos(pitchToCenter);
                double centerX = Math.cos(yawToCenter) * horizontal;
                double centerY = Math.sin(yawToCenter) * horizontal;
                double centerU = Math.sin(pitchToCenter);
                x = centerBaseX + (centerX - centerBaseX) * centering + swayX;
                y = centerBaseY + (centerY - centerBaseY) * centering + swayY;
                u = centerBaseU + (centerU - centerBaseU) * centering + swayU;
                length = Math.sqrt(x*x + y*y + u*u);
                if (!Double.isFinite(length) || length < 1e-6) return false;
                x /= length; y /= length; u /= length;

                baseX = centerBaseX + (centerX - centerBaseX) * centering + (baseX - centerBaseX);
                baseY = centerBaseY + (centerY - centerBaseY) * centering + (baseY - centerBaseY);
                baseU = centerBaseU + (centerU - centerBaseU) * centering + (baseU - centerBaseU);
                baseLength = Math.sqrt(baseX * baseX + baseY * baseY + baseU * baseU);
                if (!Double.isFinite(baseLength) || baseLength < 1e-6) return false;
                baseX /= baseLength; baseY /= baseLength; baseU /= baseLength;
            }
        }
        double yaw = Math.atan2(y, x);
        double pitch = Math.atan2(u, Math.hypot(x, y));
        double rawYaw = Math.atan2(baseY, baseX);
        double rawPitch = Math.atan2(baseU, Math.hypot(baseX, baseY));
        double carryYaw = 0.0, carryPitch = 0.0;
        if (sameBurst && shotMotionGain > 0) {
            double requestedYaw = Math.toDegrees(
                    clampRadians(wrapRadians(rawYaw - previousShotYaw), MAX_SHOT_MOTION_DELTA)
                            * shotMotionGain);
            double requestedPitch = Math.toDegrees(
                    clampRadians(rawPitch - previousShotPitch, MAX_SHOT_MOTION_DELTA)
                            * shotMotionGain);
            // The bullet and the visible barrel receive the same applied correction.
            // If the visual sway limit is reached, clamp the shot correction too.
            HoldSway.CarryAdjustment applied = HoldSway.addShotCarry(
                    weapon.getFullType(), requestedYaw, requestedPitch);
            carryYaw = Math.toRadians(applied.yawDegrees());
            carryPitch = Math.toRadians(applied.pitchDegrees());
            yaw += carryYaw;
            pitch += carryPitch;
            double horizontal = Math.cos(pitch);
            x = Math.cos(yaw) * horizontal;
            y = Math.sin(yaw) * horizontal;
            u = Math.sin(pitch);
        }
        try {
            Field solutionField = manager.getClass().getDeclaredField("sol");
            solutionField.setAccessible(true);
            Object solution = solutionField.get(manager);
            Object direction = solution.getClass().getField("direction").get(solution);
            // True Ballistics reads a model muzzle before the ADS arm/weapon bone
            // correction reaches the projectile. Move that spawn point by the
            // weapon's angular change around the grip (approximate grip-to-muzzle
            // lever, capped to avoid malformed model transforms causing jumps).
            Object barrel = solution.getClass().getField("barrel").get(solution);
            double bx = getNumber(barrel, "x"), by = getNumber(barrel, "y"), bu = getNumber(barrel, "u");
            double bl = Math.sqrt(bx*bx + by*by + bu*bu);
            double dx = 0, dy = 0, du = 0;
            if (Double.isFinite(bl) && bl > 0.5) {
                dx = (physicalX - bx / bl) * 0.55;
                dy = (physicalY - by / bl) * 0.55;
                du = (physicalU - bu / bl) * 0.55;
                double shift = Math.sqrt(dx*dx + dy*dy + du*du);
                if (!Double.isFinite(shift)) return false;
                if (shift > 0.25) { double scale = 0.25 / shift; dx *= scale; dy *= scale; du *= scale; }
            }
            Object muzzle = solution.getClass().getField("muzzle").get(solution);
            setNumber(muzzle, "x", getNumber(muzzle, "x") + dx);
            setNumber(muzzle, "y", getNumber(muzzle, "y") + dy);
            setNumber(muzzle, "u", getNumber(muzzle, "u") + du);
            setNumber(direction, "x", x);
            setNumber(direction, "y", y);
            setNumber(direction, "u", u);

            // This is deliberately after launch: it rewrites the live projectile
            // velocity and spawn coordinates, even if another aim hook overwrote
            // AimSolution.direction earlier in the same trigger pull.
            Object activeValue = manager.getClass().getMethod("activeProjectiles").invoke(manager);
            if (!(activeValue instanceof java.util.List<?> active)) return false;
            int changed = 0;
            for (Object projectile : active) {
                if (projectile.getClass().getField("group").get(projectile) != group) continue;
                Object origin = projectile.getClass().getField("origin").get(projectile);
                Object position = projectile.getClass().getField("position").get(projectile);
                Object previous = projectile.getClass().getField("previousPosition").get(projectile);
                setNumber(origin, "x", getNumber(origin, "x") + dx);
                setNumber(origin, "y", getNumber(origin, "y") + dy);
                setNumber(origin, "u", getNumber(origin, "u") + du);
                setNumber(position, "x", getNumber(position, "x") + dx);
                setNumber(position, "y", getNumber(position, "y") + dy);
                setNumber(position, "u", getNumber(position, "u") + du);
                setNumber(previous, "x", getNumber(previous, "x") + dx);
                setNumber(previous, "y", getNumber(previous, "y") + dy);
                setNumber(previous, "u", getNumber(previous, "u") + du);
                double speed = getNumber(projectile, "muzzleVelocity");
                Object velocity = projectile.getClass().getField("velocity").get(projectile);
                setNumber(velocity, "x", x * speed);
                setNumber(velocity, "y", y * speed);
                setNumber(velocity, "u", u * speed);
                changed++;
            }
            if (changed == 0) return false;
            // Keep the visible barrel in sync with the exact ray handed to True
            // Ballistics. Previously only the small burst delta was animated,
            // while the larger first-shot/aim-centering correction affected
            // the projectile alone, detaching impacts from the gun's movement.
            HoldSway.mirrorShotDirection(weapon.getFullType(),
                    Math.toDegrees(wrapRadians(yaw - visualBaseYaw)),
                    Math.toDegrees(pitch - visualBasePitch));
            previousShotWeapon = weapon.getFullType();
            previousShotAt = shotAt;
            previousShotYaw = rawYaw;
            previousShotPitch = rawPitch;
            if (shotCenteringActive) {
                previousCenteringWeapon = weapon.getFullType();
                previousCenteringShotAt = shotAt;
                centeringBurstShotCount = centeringShotIndex;
            }
            if (!trueBallisticsAnnounced) {
                trueBallisticsAnnounced = true;
                System.out.println("[ViewpointGael] corrected live True Ballistics projectiles: muzzle position and pitch/yaw direction now follow the physical ADS weapon axis");
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[ViewpointGael] Could not correct the live True Ballistics projectile: " + error);
            return false;
        }
    }

    private static double getNumber(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getField(name).getDouble(target);
    }

    private static void setNumber(Object target, String name, double value) throws ReflectiveOperationException {
        Field field = target.getClass().getField(name);
        field.setDouble(target, value);
    }

    private static double centeringBurstEffect(int shot) {
        if (shot <= 3) return 1.0;
        if (shot <= 5) return 0.40;
        return Math.max(0.0, 0.40 - (shot - 5) * 0.02);
    }

    private static double wrapRadians(double angle) {
        while (angle > Math.PI) angle -= Math.PI * 2.0;
        while (angle < -Math.PI) angle += Math.PI * 2.0;
        return angle;
    }

    private static double clampRadians(double angle, double limit) {
        return Math.max(-limit, Math.min(limit, angle));
    }

    static boolean writeDirection(Vector3 direction, double x, double y, double up) {
        if (direction == null) return false;
        double z = up / FLOOR_HEIGHT;
        double length = Math.sqrt(x * x + y * y + z * z);
        if (!Double.isFinite(length) || length < 1e-6) return false;
        direction.set((float) (x / length), (float) (y / length), (float) (z / length));
        return true;
    }

    /** Convert ADS render axes (-worldX, up*sqrt6, -worldY) to native ballistics axes. */
    static boolean writePhysicalDirection(Vector3 direction, double renderX, double renderUp, double renderY) {
        return writeDirection(direction, -renderX, -renderY, renderUp);
    }

    private record ShotOrigin(String weaponId, float x, float y, float z, long at) {}
    private record WeaponPose(String weaponId, Matrix4f model, float angle, long at) {}
    private static final class OriginScratch {
        final Vector3f modelOffset = new Vector3f();
        final Vector3 worldOffset = new Vector3();
    }

    private GaelNativeShot() {}
}
