package viewpointgael;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import pvads.GaelWeaponMotion;
import pvads.ADS;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.characters.IsoPlayer;
import java.lang.reflect.Field;

/** Angular motion about the weapon grip, independent of positional body motion. */
public final class HoldSway {
    private static final float LIMIT = 25;
    private static final long MAX_AGE_NS = 500_000_000L;
    private static volatile State state;
    private static boolean reported, reportedFallback, failed;
    private static final ThreadLocal<Scratch> scratch = ThreadLocal.withInitial(Scratch::new);
    private static final Field ARM_BONES = field("armBones"), POSE = field("M"), BARREL = field("dw"), WEAPON = field("W"), BLEND = field("eShared");

    private static Field field(String name) {
        try { Field value = ADS.class.getDeclaredField(name); value.setAccessible(true); return value; }
        catch (ReflectiveOperationException error) { throw new ExceptionInInitializerError(error); }
    }

    static boolean set(String weapon, double yaw, double pitch) {
        return set(weapon,yaw,pitch,0);
    }

    static boolean set(String weapon, double yaw, double pitch, double roll) {
        if (weapon == null || !Double.isFinite(yaw) || !Double.isFinite(pitch) || !Double.isFinite(roll)) return false;
        state = new State(weapon, (float)Math.max(-LIMIT, Math.min(LIMIT,yaw)),
                (float)Math.max(-LIMIT, Math.min(LIMIT,pitch)),
                (float)Math.max(-LIMIT, Math.min(LIMIT,roll)), System.nanoTime());
        return true;
    }

    /** Apply after ADS has finished composing and writing the final arm/weapon bone transforms. */
    public static void applyToWeaponBones(Object animationPlayer) {
        State value = state;
        if (failed || value == null || System.nanoTime()-value.at > MAX_AGE_NS
                || (value.yaw == 0 && value.pitch == 0 && value.roll == 0)) return;
        IsoPlayer player = IsoPlayer.players[0];
        var item = player == null ? null : player.getPrimaryHandItem();
        if (item == null || !value.weaponId.equals(item.getFullType())) return;
        try {
            Scratch work = scratch.get();
            Matrix4f pose = (Matrix4f) POSE.get(null);
            ((Matrix4f) WEAPON.get(null)).transformDirection((Vector3f) BARREL.get(null), work.forward);
            pose.transformDirection(work.forward).normalize();
            if (!GaelWeaponMotion.gripPivot(player, animationPlayer, pose, work.pivot)) {
                // Gael weapon models such as the MP5 can have no self grip
                // attachment. Pivot around the transformed model origin with
                // a short rearward offset so their barrel still receives sway.
                ((Matrix4f) WEAPON.get(null)).transformPosition(0, 0, 0, work.pivot);
                pose.transformPosition(work.pivot);
                work.pivot.fma(-0.15f, work.forward);
                if (!reportedFallback) {
                    reportedFallback = true;
                    System.out.println("[ViewpointGael] weapon model has no grip attachment; using model-origin sway pivot");
                }
            }
            float blend = BLEND.getFloat(null);
            if (blend <= 0) return;
            buildRotation(work.pivot, work.forward, value.yaw, value.pitch, value.roll, blend, work.rotation);
            int[] bones = (int[]) ARM_BONES.get(null);
            AnimationPlayer ap = (AnimationPlayer) animationPlayer;
            // Rotate both arm chains and the held prop around the hand joint.
            // Filtering to armIsProp moves only the gun and leaves the arms behind.
            for (int i = 0; i < bones.length; i++) {
                org.lwjgl.util.vector.Matrix4f bone = ap.getModelTransformAt(bones[i]);
                PZMath.convertMatrix(bone, work.bone);
                work.bone.transpose();
                work.rotation.mul(work.bone, work.bone);
                work.bone.transpose();
                PZMath.convertMatrix(work.bone, bone);
            }
            if (!reported) {
                reported = true;
                System.out.println("[ViewpointGael] post-ADS weapon-bone yaw/pitch motion active (v11): " + value.weaponId);
            }
        } catch (Throwable error) {
            failed = true;
            System.err.println("[ViewpointGael] angular weapon motion unavailable: " + error);
        }
    }

    static void rotatePose(Vector3f sight, Vector3f forward, float yaw, float pitch, float blend, Matrix4f pose) {
        Scratch work = scratch.get();
        // Only used for models without a grip attachment. This rear point moves
        // with the aligned weapon, rather than with an arbitrary camera offset.
        pose.transformPosition(sight, work.pivot);
        work.pivot.fma(-0.15f,forward);
        rotateAroundPivot(work.pivot,forward,yaw,pitch,blend,pose);
    }

    static void rotateAroundPivot(Vector3f pivot, Vector3f forward, float yaw, float pitch, float blend, Matrix4f pose) {
        rotateAroundPivot(pivot,forward,yaw,pitch,0,blend,pose);
    }

    static void rotateAroundPivot(Vector3f pivot, Vector3f forward, float yaw, float pitch, float roll, float blend, Matrix4f pose) {
        Scratch work = scratch.get();
        buildRotation(pivot, forward, yaw, pitch, roll, blend, work.rotation);
        work.rotation.mul(pose,pose);
    }

    private static void buildRotation(Vector3f pivot, Vector3f forward, float yaw, float pitch, float roll, float blend, Matrix4f out) {
        Scratch work = scratch.get();
        work.pivot.set(pivot);
        work.right.set(forward).cross(0,1,0);
        if (work.right.lengthSquared() < 1e-6f) work.right.set(1,0,0);
        else work.right.normalize();
        float amount = Math.min(1,blend);
        out.identity().translate(work.pivot)
                .rotate((float)Math.toRadians(yaw*amount),0,1,0)
                .rotate((float)Math.toRadians(pitch*amount),work.right.x,work.right.y,work.right.z)
                .rotate((float)Math.toRadians(roll*amount),forward.x,forward.y,forward.z)
                .translate(-work.pivot.x,-work.pivot.y,-work.pivot.z);
    }

    private record State(String weaponId, float yaw, float pitch, float roll, long at) {}
    private static final class Scratch {
        final Vector3f pivot = new Vector3f(), right = new Vector3f(), forward = new Vector3f();
        final Matrix4f rotation = new Matrix4f(), bone = new Matrix4f();
    }
    private HoldSway() {}
}
