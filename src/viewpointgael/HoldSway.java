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
    private static volatile ShotCarry shotCarry;
    private static final long SHOT_CARRY_WINDOW_NS = 300_000_000L;
    private static boolean reported, reportedFallback, reportedFailure;
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

    /** Mirror the extra per-shot ballistic correction in the visible arm/weapon pose. */
    public static CarryAdjustment addShotCarry(String weapon, double yawDegrees, double pitchDegrees) {
        if (weapon == null || !Double.isFinite(yawDegrees) || !Double.isFinite(pitchDegrees)) {
            return new CarryAdjustment(0.0, 0.0);
        }
        long now = System.nanoTime();
        ShotCarry previous = activeCarry(weapon, now);
        float fade = carryFade(previous, now);
        double previousYaw = previous == null ? 0.0 : previous.yaw * fade;
        double previousPitch = previous == null ? 0.0 : previous.pitch * fade;
        float yaw = (float) Math.max(-LIMIT, Math.min(LIMIT,
                previousYaw + yawDegrees));
        float pitch = (float) Math.max(-LIMIT, Math.min(LIMIT,
                previousPitch + pitchDegrees));
        shotCarry = new ShotCarry(weapon, yaw, pitch, now);
        return new CarryAdjustment(yaw - previousYaw, pitch - previousPitch);
    }

    /** Set the visible post-shot pose to the final projectile ray relative to the unsnapped weapon axis. */
    public static void mirrorShotDirection(String weapon, double yawDegrees, double pitchDegrees) {
        if (weapon == null || !Double.isFinite(yawDegrees) || !Double.isFinite(pitchDegrees)) return;
        // This is not ordinary recoil sway: it mirrors the angular correction
        // already applied to the projectile. Clamping it to LIMIT made the gun
        // stop moving while the bullet kept correcting toward the reticle.
        float yaw = (float) yawDegrees;
        float pitch = (float) pitchDegrees;
        shotCarry = new ShotCarry(weapon, yaw, pitch, System.nanoTime());
    }

    private static ShotCarry activeCarry(String weapon, long now) {
        ShotCarry value = shotCarry;
        return value != null && value.weaponId.equals(weapon)
                && now >= value.at && now - value.at < SHOT_CARRY_WINDOW_NS ? value : null;
    }

    private static float carryFade(ShotCarry value, long now) {
        if (value == null || now < value.at) return 0.0f;
        float t = Math.min(1.0f, (now - value.at) / (float) SHOT_CARRY_WINDOW_NS);
        return 1.0f - t * t * (3.0f - 2.0f * t);
    }

    /** Apply the same live post-ADS bone rotation to the direction used by ballistics. */
    public static void applyToShotDirection(String weaponId, Vector3f direction) {
        applyToShotDirection(weaponId, direction, true);
    }

    /** Apply only the regular animation sway, excluding the extra shot-carry overlay. */
    public static void applySwayToShotDirection(String weaponId, Vector3f direction) {
        applyToShotDirection(weaponId, direction, false);
    }

    private static void applyToShotDirection(String weaponId, Vector3f direction,
                                             boolean includeShotCarry) {
        State value = state;
        long now = System.nanoTime();
        ShotCarry carry = includeShotCarry ? activeCarry(weaponId, now) : null;
        boolean hasState = value != null && weaponId != null && weaponId.equals(value.weaponId)
                && now >= value.at && now - value.at <= MAX_AGE_NS;
        if (direction == null || weaponId == null || (!hasState && carry == null)) return;
        float blend;
        try { blend = BLEND.getFloat(null); }
        catch (IllegalAccessException error) { return; }
        if (!Float.isFinite(blend) || blend <= 0) return;
        float fade = carryFade(carry, now);
        float yaw = (hasState ? value.yaw : 0.0f) + (carry == null ? 0.0f : carry.yaw * fade);
        float pitch = (hasState ? value.pitch : 0.0f) + (carry == null ? 0.0f : carry.pitch * fade);
        float roll = hasState ? value.roll : 0.0f;
        if (yaw == 0.0f && pitch == 0.0f && roll == 0.0f) return;
        Scratch work = scratch.get();
        work.forward.set(direction);
        if (work.forward.lengthSquared() < 1.0e-8f) return;
        work.forward.normalize();
        work.pivot.zero();
        buildRotation(work.pivot, work.forward, yaw, pitch, roll, blend, work.rotation);
        work.rotation.transformDirection(direction).normalize();
    }

    /** Apply after ADS has finished composing and writing the final arm/weapon bone transforms. */
    public static void applyToWeaponBones(Object animationPlayer) {
        State value = state;
        long now = System.nanoTime();
        ShotCarry carry = shotCarry;
        boolean hasState = value != null && now >= value.at && now - value.at <= MAX_AGE_NS;
        boolean hasCarry = carry != null && now >= carry.at
                && now - carry.at < SHOT_CARRY_WINDOW_NS;
        if (!hasState && !hasCarry) return;
        IsoPlayer player = IsoPlayer.players[0];
        // ADS.posed is also called for remote players. Its OnExit patch runs
        // for those calls too, but ADS.armBones belongs to the local skeleton;
        // applying those indices to a remote AnimationPlayer can throw and
        // permanently disable recoil sway for the rest of the session.
        if (player == null || animationPlayer != player.getAnimationPlayer()) return;
        var item = player == null ? null : player.getPrimaryHandItem();
        String weaponId = hasState ? value.weaponId : carry.weaponId;
        if (item == null || !weaponId.equals(item.getFullType())) return;
        hasCarry = hasCarry && weaponId.equals(carry.weaponId);
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
            float carryAmount = carryFade(hasCarry ? carry : null, now);
            float yaw = (hasState ? value.yaw : 0.0f) + (hasCarry ? carry.yaw * carryAmount : 0.0f);
            float pitch = (hasState ? value.pitch : 0.0f) + (hasCarry ? carry.pitch * carryAmount : 0.0f);
            float roll = hasState ? value.roll : 0.0f;
            if (yaw == 0.0f && pitch == 0.0f && roll == 0.0f) return;
            buildRotation(work.pivot, work.forward, yaw, pitch, roll, blend, work.rotation);
            // `pivot` and `forward` are in rendered/world space, while
            // AnimationPlayer model transforms are in model space. Conjugate
            // the world rotation through ADS.M so the same angular change is
            // applied in the coordinate system used by the bone matrices.
            work.localRotation.set(pose).invert()
                    .mul(work.rotation)
                    .mul(pose);
            int[] bones = (int[]) ARM_BONES.get(null);
            AnimationPlayer ap = (AnimationPlayer) animationPlayer;
            // Rotate both arm chains and the held prop around the hand joint.
            // Filtering to armIsProp moves only the gun and leaves the arms behind.
            for (int i = 0; i < bones.length; i++) {
                org.lwjgl.util.vector.Matrix4f bone = ap.getModelTransformAt(bones[i]);
                PZMath.convertMatrix(bone, work.bone);
                work.bone.transpose();
                work.localRotation.mul(work.bone, work.bone);
                work.bone.transpose();
                PZMath.convertMatrix(work.bone, bone);
            }
            if (!reported) {
                reported = true;
                System.out.println("[ViewpointGael] post-ADS weapon-bone yaw/pitch motion active (v11): " + value.weaponId);
            }
        } catch (Throwable error) {
            // Bone layouts can briefly be unavailable while PZ swaps models.
            // Keep retrying on later frames instead of latching sway off.
            if (!reportedFailure) {
                reportedFailure = true;
                System.err.println("[ViewpointGael] angular weapon motion frame skipped: " + error);
            }
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
    private record ShotCarry(String weaponId, float yaw, float pitch, long at) {}
    public record CarryAdjustment(double yawDegrees, double pitchDegrees) {}
    private static final class Scratch {
        final Vector3f pivot = new Vector3f(), right = new Vector3f(), forward = new Vector3f();
        final Matrix4f rotation = new Matrix4f(), localRotation = new Matrix4f(), bone = new Matrix4f();
    }
    private HoldSway() {}
}
