package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.inventory.types.HandWeapon;
import zombie.iso.Vector3;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import java.lang.reflect.Field;

/** Shares the calibrated ADS shot direction with Build 42's native ballistics. */
public final class GaelNativeShot {
    private static final double FLOOR_HEIGHT = 2.4494895935058594;
    private static final ThreadLocal<Vector3f> SHOT_DIRECTION = ThreadLocal.withInitial(Vector3f::new);
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
        // Short gameplay aim assist: after a full ADS ramp, the first three
        // shots snap to the camera-center ray in ideal conditions, overriding
        // the weapon's physical barrel direction. Condition penalties apply.
        if (shotCenteringActive && centeringShotIndex <= 3 && shotCentering >= 0.99) {
            centering = 1.0;
        }
        if (centering > 0) {
            double yawToCenter = VP.yaw(), pitchToCenter = VP.pitch();
            if (Double.isFinite(yawToCenter) && Double.isFinite(pitchToCenter)) {
                double horizontal = Math.cos(pitchToCenter);
                double centerX = Math.cos(yawToCenter) * horizontal;
                double centerY = Math.sin(yawToCenter) * horizontal;
                double centerU = Math.sin(pitchToCenter);
                x += (centerX - x) * centering;
                y += (centerY - y) * centering;
                u += (centerU - u) * centering;
                length = Math.sqrt(x*x + y*y + u*u);
                if (!Double.isFinite(length) || length < 1e-6) return false;
                x /= length; y /= length; u /= length;
            }
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
                System.out.println("[ViewpointGael] True Ballistics now uses the physical ADS weapon axis before projectile spawn");
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.err.println("[ViewpointGael] Could not correct the True Ballistics aim solution: " + error);
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
    private static final class OriginScratch {
        final Vector3f modelOffset = new Vector3f();
        final Vector3 worldOffset = new Vector3();
    }

    private GaelNativeShot() {}
}
