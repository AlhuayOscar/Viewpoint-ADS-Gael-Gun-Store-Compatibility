package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.inventory.types.HandWeapon;
import zombie.iso.Vector3;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import java.lang.reflect.Field;
import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;

/** Shares the calibrated ADS shot direction with Build 42's native ballistics. */
public final class GaelNativeShot {
    private static final double FLOOR_HEIGHT = 2.4494895935058594;
    private static final ThreadLocal<Vector3f> SHOT_DIRECTION = ThreadLocal.withInitial(Vector3f::new);
    private static final ThreadLocal<OriginScratch> ORIGIN_SCRATCH = ThreadLocal.withInitial(OriginScratch::new);
    private static final ThreadLocal<ShotAssist> PENDING_ASSIST = new ThreadLocal<>();
    private static final Map<Object, ShotAssist> GUIDED_PROJECTILES =
            Collections.synchronizedMap(new WeakHashMap<>());
    private static volatile ShotOrigin shotOrigin;
    private static volatile WeaponPose weaponPose;
    private static boolean announced;
    private static boolean originAnnounced;
    private static boolean trueBallisticsAnnounced;
    private static boolean trueBallisticsProjectilesAnnounced;
    private static boolean trueBallisticsProjectilesMissingAnnounced;
    private static boolean trueBallisticsAssistAnnounced;
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

    /** Model-space offsets applied to True Ballistics' actual muzzle; units are weapon mesh units. */
    public static boolean setShotOrigin(String weapon, double x, double y, double z) {
        if (weapon == null || !Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z)) return false;
        shotOrigin = new ShotOrigin(weapon, clamp(x), clamp(y), clamp(z), System.nanoTime());
        return true;
    }

    private static float clamp(double value) { return (float) Math.max(-2.0, Math.min(2.0, value)); }

    /** Extra share of the weapon's angular movement between consecutive shots (0 disables carry). */
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

    /** Physical ADS weapon axis in tile-space units for Viewpoint launcher aim. */
    public static double launcherAxis(int component) {
        IsoPlayer player = IsoPlayer.players[0];
        WeaponPose pose = weaponPose;
        if (player == null || !player.isAiming() || !VP.firstPerson() || VP.freeCam()
                || pose == null || System.nanoTime() - pose.at > 500_000_000L
                || !(player.getPrimaryHandItem() instanceof HandWeapon weapon)
                || !pose.weaponId.equals(weapon.getFullType())) return Double.NaN;
        Vector3f direction = SHOT_DIRECTION.get();
        if (!GaelWeaponMotion.shotDirection(pose.angle, direction)) return Double.NaN;
        return switch (component) {
            case 0 -> -direction.x;
            case 1 -> -direction.z;
            case 2 -> direction.y / FLOOR_HEIGHT;
            default -> Double.NaN;
        };
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

    static boolean writeDirection(Vector3 direction, double[] ray) {
        if (ray == null || ray.length < 6) return false;
        return writeDirection(direction, ray[3], ray[4], ray[5]);
    }

    /**
     * Move True Ballistics' resolved muzzle before AimProvider checks nearby walls
     * and before BallisticsManager spawns a projectile or records its debug trail.
     */
    public static void applyTrueBallisticsMuzzleCalibration(Object character, Object muzzle) {
        IsoPlayer player = IsoPlayer.players[0];
        WeaponPose pose = weaponPose;
        ShotOrigin calibration = shotOrigin;
        if (character != player || player == null || !player.isAiming()
                || !(player.getPrimaryHandItem() instanceof HandWeapon weapon)
                || !weapon.isAimedFirearm() || !VP.firstPerson() || VP.freeCam()
                || pose == null || calibration == null
                || System.nanoTime() - pose.at > 500_000_000L
                || System.nanoTime() - calibration.at > 500_000_000L
                || !pose.weaponId.equals(weapon.getFullType())
                || !calibration.weaponId.equals(weapon.getFullType())
                || (calibration.x == 0f && calibration.y == 0f && calibration.z == 0f)) return;
        try {
            OriginScratch work = ORIGIN_SCRATCH.get();
            pose.model.transformDirection(work.modelOffset.set(calibration.x, calibration.y, calibration.z));
            work.worldOffset.set(work.modelOffset.x, work.modelOffset.y, work.modelOffset.z);
            Model.vectorToWorldCoords(0f, 0f, 0f, pose.angle, work.worldOffset);
            if (!Float.isFinite(work.worldOffset.x) || !Float.isFinite(work.worldOffset.y)
                    || !Float.isFinite(work.worldOffset.z)) return;
            // PZ world X/Y/up to True Ballistics tile X/Y/meters-up axes.
            setNumber(muzzle, "x", getNumber(muzzle, "x") - work.worldOffset.x);
            setNumber(muzzle, "y", getNumber(muzzle, "y") - work.worldOffset.y);
            setNumber(muzzle, "u", getNumber(muzzle, "u") + work.worldOffset.z);
            if (!originAnnounced) {
                originAnnounced = true;
                System.out.println("[ViewpointGael] calibrated muzzle applied during True Ballistics muzzle resolution");
            }
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[ViewpointGael] Could not calibrate the True Ballistics muzzle: " + error);
        }
    }

    /** Apply Gael's physical ADS axis before True Ballistics creates projectiles and debug trails. */
    public static boolean correctTrueBallisticsSolution(Object shooter, Object weaponObject, Object solution) {
        IsoPlayer player = IsoPlayer.players[0];
        WeaponPose pose = weaponPose;
        if (shooter != player || !(weaponObject instanceof HandWeapon weapon) || player == null
                || !player.isAiming() || !weapon.isAimedFirearm() || !VP.firstPerson() || VP.freeCam()
                || !GaelWeaponMotion.ready() || pose == null
                || System.nanoTime() - pose.at > 500_000_000L
                || !pose.weaponId.equals(weapon.getFullType())) return false;
        Vector3f rendered = SHOT_DIRECTION.get();
        if (!GaelWeaponMotion.shotDirection(pose.angle, rendered)) return false;
        // True Ballistics V3 uses tile X/Y and meters-up U. ADS render axes are
        // (-worldX, up, -worldY), the same mapping as the native shot bridge.
        double x = -rendered.x, y = -rendered.z, u = rendered.y;
        double length = Math.sqrt(x*x + y*y + u*u);
        if (!Double.isFinite(length) || length < 1e-6) return false;
        x /= length; y /= length; u /= length;
        long shotAt = System.nanoTime();
        boolean sameCenteringBurst = shotCenteringActive
                && weapon.getFullType().equals(previousCenteringWeapon)
                && shotAt > previousCenteringShotAt
                && shotAt - previousCenteringShotAt <= CENTERING_BURST_WINDOW_NANOS;
        int centeringShotIndex = sameCenteringBurst ? centeringBurstShotCount + 1 : 1;
        double centering = shotCenteringActive
                ? shotCentering * centeringBurstEffect(centeringShotIndex) : 0.0;
        // Keep the actual barrel direction at launch. Eligible shots will curve
        // toward True Ballistics' camera-ray aim point during their first tiles.
        if (shotCenteringActive && centeringShotIndex <= 3 && shotCentering >= 0.99) {
            centering = 1.0;
        }
        double yaw = Math.atan2(y, x);
        double pitch = Math.atan2(u, Math.hypot(x, y));
        boolean sameBurst = weapon.getFullType().equals(previousShotWeapon)
                && shotAt > previousShotAt && shotAt - previousShotAt <= SHOT_MOTION_WINDOW_NANOS;
        double rawYaw = yaw, rawPitch = pitch;
        if (sameBurst && shotMotionGain > 0) {
            double deltaYaw = clampRadians(wrapRadians(rawYaw - previousShotYaw), MAX_SHOT_MOTION_DELTA);
            double deltaPitch = clampRadians(rawPitch - previousShotPitch, MAX_SHOT_MOTION_DELTA);
            yaw += deltaYaw * shotMotionGain;
            pitch += deltaPitch * shotMotionGain;
            double horizontal = Math.cos(pitch);
            x = Math.cos(yaw) * horizontal;
            y = Math.sin(yaw) * horizontal;
            u = Math.sin(pitch);
        }
        try {
            Object direction = solution.getClass().getField("direction").get(solution);
            setNumber(direction, "x", x);
            setNumber(direction, "y", y);
            setNumber(direction, "u", u);
            ShotAssist pendingAssist = null;
            if (centering > 0) {
                Object aimPoint = solution.getClass().getField("aimPoint").get(solution);
                double targetX = getNumber(aimPoint, "x");
                double targetY = getNumber(aimPoint, "y");
                double targetU = getNumber(aimPoint, "u");
                if (Double.isFinite(targetX) && Double.isFinite(targetY) && Double.isFinite(targetU)) {
                    AssistAngle angle = assistAngleFactor(solution, x, y, u,
                            targetX, targetY, targetU);
                    double strength = centering * angle.factor;
                    System.out.println("[ViewpointGael] shot-assist weapon=" + weapon.getFullType()
                            + " burstShot=" + centeringShotIndex
                            + " centering=" + centering
                            + " muzzleAimAngle=" + angle.degrees
                            + " angleFactor=" + angle.factor
                            + " strength=" + strength);
                    if (strength > 0.01) pendingAssist = new ShotAssist(targetX, targetY,
                            targetU, strength, 0.0, 0.0, 0.0);
                }
            }
            PENDING_ASSIST.set(pendingAssist);
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
                System.out.println("[ViewpointGael] solved True Ballistics direction now follows the rendered ADS weapon axis");
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[ViewpointGael] Could not correct the True Ballistics aim solution: " + error);
            return false;
        }
    }

    /**
     * AimProvider.solve is not reliably patchable in every load order. At launch
     * exit, True Ballistics has solved the ray and created this group's
     * projectiles, so update the solution and their velocities before physics ticks.
     */
    public static boolean correctTrueBallisticsShot(Object manager, Object group) {
        IsoPlayer player = IsoPlayer.players[0];
        if (manager == null || group == null || player == null) return false;
        PENDING_ASSIST.remove();
        try {
            Field solutionField = manager.getClass().getDeclaredField("sol");
            solutionField.setAccessible(true);
            Object solution = solutionField.get(manager);
            if (!correctTrueBallisticsSolution(player, player.getPrimaryHandItem(), solution)) return false;

            Object direction = solution.getClass().getField("direction").get(solution);
            double x = getNumber(direction, "x");
            double y = getNumber(direction, "y");
            double u = getNumber(direction, "u");
            ShotAssist pendingAssist = PENDING_ASSIST.get();
            PENDING_ASSIST.remove();
            Object activeValue = manager.getClass().getMethod("activeProjectiles").invoke(manager);
            if (!(activeValue instanceof java.util.List<?> active)) return false;
            int changed = 0;
            for (Object projectile : active) {
                if (projectile.getClass().getField("group").get(projectile) != group) continue;
                double speed = getNumber(projectile, "muzzleVelocity");
                Object velocity = projectile.getClass().getField("velocity").get(projectile);
                setNumber(velocity, "x", x * speed);
                setNumber(velocity, "y", y * speed);
                setNumber(velocity, "u", u * speed);
                if (pendingAssist != null) {
                    GUIDED_PROJECTILES.put(projectile, pendingAssist.withProgress(
                            getNumber(projectile, "age"), getNumber(projectile, "traveled")));
                }
                changed++;
            }
            if (player.getPrimaryHandItem() instanceof HandWeapon weapon
                    && "Base.M4".equals(weapon.getFullType())) {
                System.out.println("[ViewpointGael] shot-assist launch weapon=Base.M4 projectiles=" + changed
                        + " guided=" + (pendingAssist != null)
                        + " strength=" + (pendingAssist == null ? 0.0 : pendingAssist.strength));
            }
            if (changed == 0) {
                if (!trueBallisticsProjectilesMissingAnnounced) {
                    trueBallisticsProjectilesMissingAnnounced = true;
                    System.err.println("[ViewpointGael] True Ballistics launch hook found no live projectiles for the shot group");
                }
                return false;
            }
            if (!trueBallisticsProjectilesAnnounced) {
                trueBallisticsProjectilesAnnounced = true;
                System.out.println("[ViewpointGael] redirected " + changed
                        + " live True Ballistics projectile(s) to match the visible weapon deviation");
            }
            if (pendingAssist != null && !trueBallisticsAssistAnnounced) {
                trueBallisticsAssistAnnounced = true;
                System.out.println("[ViewpointGael] first-shot aim assist curves toward the blue aim ray over the first 4 tiles");
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[ViewpointGael] Could not redirect live True Ballistics projectiles: " + error);
            return false;
        }
    }

    /** Smoothly curve assisted projectiles toward the camera-ray hit point. */
    public static void guideTrueBallisticsProjectile(Object projectile, double frameSeconds) {
        if (projectile == null || !Double.isFinite(frameSeconds) || frameSeconds <= 0) return;
        ShotAssist assist = GUIDED_PROJECTILES.get(projectile);
        if (assist == null) return;
        try {
            double age = getNumber(projectile, "age");
            double traveled = getNumber(projectile, "traveled");
            double ageSinceLaunch = Math.max(0.0, age - assist.startAge);
            double distanceSinceLaunch = Math.max(assist.guidedDistance,
                    traveled - assist.startTravel);
            if (ageSinceLaunch >= AIM_ASSIST_MAX_SECONDS
                    || distanceSinceLaunch >= AIM_ASSIST_MAX_DISTANCE) {
                GUIDED_PROJECTILES.remove(projectile);
                return;
            }

            Object position = projectile.getClass().getField("position").get(projectile);
            Object velocity = projectile.getClass().getField("velocity").get(projectile);
            double vx = getNumber(velocity, "x"), vy = getNumber(velocity, "y");
            double vu = getNumber(velocity, "u");
            double speed = Math.sqrt(vx * vx + vy * vy + vu * vu);
            if (!Double.isFinite(speed) || speed < 1.0e-6) {
                GUIDED_PROJECTILES.remove(projectile);
                return;
            }
            double dx = assist.targetX - getNumber(position, "x");
            double dy = assist.targetY - getNumber(position, "y");
            double du = assist.targetU - getNumber(position, "u");
            double targetLength = Math.sqrt(dx * dx + dy * dy + du * du);
            if (!Double.isFinite(targetLength) || targetLength < 1.0e-4) {
                GUIDED_PROJECTILES.remove(projectile);
                return;
            }
            dx /= targetLength;
            dy /= targetLength;
            du /= targetLength;

            double remaining = AIM_ASSIST_MAX_DISTANCE - distanceSinceLaunch;
            double stepDistance = Math.min(remaining,
                    Math.min(1.0, speed * Math.min(frameSeconds, 0.05)));
            if (stepDistance <= 0) return;
            double alpha = 1.0 - Math.exp(-AIM_ASSIST_CURVE_RATE * stepDistance * assist.strength);
            double nx = vx / speed + (dx - vx / speed) * alpha;
            double ny = vy / speed + (dy - vy / speed) * alpha;
            double nu = vu / speed + (du - vu / speed) * alpha;
            double nextLength = Math.sqrt(nx * nx + ny * ny + nu * nu);
            if (!Double.isFinite(nextLength) || nextLength < 1.0e-6) return;
            setNumber(velocity, "x", nx / nextLength * speed);
            setNumber(velocity, "y", ny / nextLength * speed);
            setNumber(velocity, "u", nu / nextLength * speed);
            GUIDED_PROJECTILES.put(projectile, assist.advance(stepDistance));
        } catch (ReflectiveOperationException | RuntimeException error) {
            GUIDED_PROJECTILES.remove(projectile);
        }
    }

    private static final double AIM_ASSIST_MAX_SECONDS = 0.12;
    private static final double AIM_ASSIST_MAX_DISTANCE = 4.0;
    private static final double AIM_ASSIST_CURVE_RATE = 0.9;

    private static AssistAngle assistAngleFactor(Object solution, double x, double y, double u,
                                                double targetX, double targetY, double targetU)
            throws ReflectiveOperationException {
        Object muzzle = solution.getClass().getField("muzzle").get(solution);
        double dx = targetX - getNumber(muzzle, "x");
        double dy = targetY - getNumber(muzzle, "y");
        double du = targetU - getNumber(muzzle, "u");
        double length = Math.sqrt(dx * dx + dy * dy + du * du);
        if (!Double.isFinite(length) || length < 1.0e-4) return new AssistAngle(0.0, 0.0);
        double dot = (x * dx + y * dy + u * du) / length;
        double angle = Math.toDegrees(Math.acos(Math.max(-1.0, Math.min(1.0, dot))));
        // Small sway gets strong help; large deviations are mostly left alone.
        double factor = Math.max(0.0, Math.min(1.0, (40.0 - Math.max(8.0, angle)) / 32.0));
        return new AssistAngle(angle, factor);
    }

    private static double getNumber(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getField(name).getDouble(target);
    }

    private static void setNumber(Object target, String name, double value) throws ReflectiveOperationException {
        Field field = target.getClass().getField(name);
        field.setDouble(target, value);
    }

    private static double wrapRadians(double angle) {
        while (angle > Math.PI) angle -= Math.PI * 2.0;
        while (angle < -Math.PI) angle += Math.PI * 2.0;
        return angle;
    }

    private static double clampRadians(double angle, double limit) {
        return Math.max(-limit, Math.min(limit, angle));
    }

    private static double centeringBurstEffect(int shot) {
        if (shot <= 3) return 1.0;
        if (shot <= 5) return 0.40;
        return Math.max(0.0, 0.40 - (shot - 5) * 0.02);
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
    private record AssistAngle(double degrees, double factor) {}
    private record ShotAssist(double targetX, double targetY, double targetU, double strength,
                              double startAge, double startTravel, double guidedDistance) {
        ShotAssist withProgress(double age, double traveled) {
            return new ShotAssist(targetX, targetY, targetU, strength, age, traveled, 0.0);
        }
        ShotAssist advance(double distance) {
            return new ShotAssist(targetX, targetY, targetU, strength,
                    startAge, startTravel, guidedDistance + distance);
        }
    }
    private static final class OriginScratch {
        final Vector3f modelOffset = new Vector3f();
        final Vector3 worldOffset = new Vector3();
    }

    private GaelNativeShot() {}
}
