package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.Model;
import zombie.inventory.types.HandWeapon;
import zombie.iso.Vector3;
import org.joml.Matrix4f;
import org.joml.Vector3f;

/** Shares the calibrated ADS shot direction with Build 42's native ballistics. */
public final class GaelNativeShot {
    private static final double FLOOR_HEIGHT = 2.4494895935058594;
    private static final ThreadLocal<double[]> RAY = ThreadLocal.withInitial(() -> new double[7]);
    private static final ThreadLocal<OriginScratch> ORIGIN_SCRATCH = ThreadLocal.withInitial(OriginScratch::new);
    private static volatile ShotOrigin shotOrigin;
    private static volatile WeaponPose weaponPose;
    private static boolean announced;
    private static boolean originAnnounced;

    /** Model-space offsets from the weapon's normal muzzle point; units are the weapon mesh's units. */
    public static boolean setShotOrigin(String weapon, double x, double y, double z) {
        if (weapon == null || !Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(z)) return false;
        shotOrigin = new ShotOrigin(weapon, clamp(x), clamp(y), clamp(z), System.nanoTime());
        return true;
    }

    private static float clamp(double value) { return (float) Math.max(-2.0, Math.min(2.0, value)); }

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
        double[] ray = RAY.get();
        // This is also the ray used by GaelSightProjection and True Ballistics.
        // Do not apply GaelBarrelRay again: separation must be applied only once.
        if (!Sight.ray(ray) || !writeDirection((Vector3) direction, ray)) return;
        if (!announced) {
            announced = true;
            System.out.println("[ViewpointGael] Native ballistics now uses the purple ADS shot ray");
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
        if (direction == null || ray == null || ray.length < 6) return false;
        double x = ray[3], y = ray[4], z = ray[5] / FLOOR_HEIGHT;
        double length = Math.sqrt(x * x + y * y + z * z);
        if (!Double.isFinite(length) || length < 1e-6) return false;
        direction.set((float) (x / length), (float) (y / length), (float) (z / length));
        return true;
    }

    private record ShotOrigin(String weaponId, float x, float y, float z, long at) {}
    private record WeaponPose(String weaponId, Matrix4f model, float angle, long at) {}
    private static final class OriginScratch {
        final Vector3f modelOffset = new Vector3f();
        final Vector3 worldOffset = new Vector3();
    }

    private GaelNativeShot() {}
}
