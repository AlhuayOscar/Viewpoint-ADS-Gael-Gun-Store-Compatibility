package pvads;

import java.lang.reflect.Field;
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Quaternionf;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.core.math.PZMath;
import zombie.core.skinnedmodel.animation.AnimationPlayer;
import zombie.scripting.objects.ModelAttachment;
import viewpointgael.HoldSway;

/** Samples the physical sight/barrel axis after the actual rendered transforms. */
public final class GaelWeaponMotion {
    private static volatile Sample sample;
    private static volatile ReferenceAlignment referenceAlignment;
    private static boolean failed;
    private static boolean announced;
    private static final ThreadLocal<Scratch> scratch = ThreadLocal.withInitial(Scratch::new);

    private static final class Fields {
        static final Field W = field(ADS.class, "W");
        static final Field M = field(ADS.class, "M");
        static final Field direction = field(ADS.class, "dw");
        static final Field drawnPose = field(ADS.class, "WP");
        static final Field presence = field(Presence.class, "shotFix");
        private static Field field(Class<?> type, String name) {
            try {
                Field value = type.getDeclaredField(name);
                value.setAccessible(true);
                return value;
            } catch (ReflectiveOperationException error) { throw new IllegalStateException(error); }
        }
    }

    /** Publishes the stable, saved sight alignment so dynamic recoil is not mistaken for calibration. */
    public static void setReferenceAlignment(String weapon, double yaw, double pitch, double roll) {
        if (weapon == null || !Double.isFinite(yaw) || !Double.isFinite(pitch) || !Double.isFinite(roll)) return;
        referenceAlignment = new ReferenceAlignment(weapon, (float) yaw, (float) pitch, (float) roll, System.nanoTime());
    }

    public static void capture(IsoPlayer player, float facing) {
        if (failed || player == null || player != IsoPlayer.players[0] || !ADS.P.valid
                || ADS.P.weaponId == null || !VP.firstPerson() || VP.freeCam()) return;
        try {
            Scratch state = scratch.get();
            GaelNativeShot.publishWeaponPose((Matrix4f) Fields.drawnPose.get(null), ADS.P.weaponId, facing);
            ReferenceAlignment alignment = referenceAlignment(ADS.P.weaponId);
            physicalDirection((Vector3f) Fields.direction.get(null), alignment.yaw,
                    alignment.pitch, alignment.roll, (Matrix4f) Fields.W.get(null),
                    (Matrix4f) Fields.M.get(null), state.direction, state.calibration);
            if (Fields.presence.getBoolean(null)) {
                Presence.fullCorrection().transformDirection(state.direction).normalize();
            }
            HoldSway.applyToShotDirection(ADS.P.weaponId, state.direction);
            ADS.cmsDirToRender(state.direction, facing, state.render);
            Core core = Core.getInstance();
            GaelSightProjection.Point point = GaelSightProjection.project(0,0,0,
                    state.render.x, state.render.y, state.render.z, VP.yaw(), VP.pitch(),
                    ADS.fovOutRad, core.getScreenWidth(), core.getScreenHeight(), 60);
            if (point == null) { sample = null; return; }
            sample = new Sample(point, ADS.P.weaponId, System.nanoTime());
            if (!announced) {
                announced = true;
                System.out.println("[ViewpointGael] Physical weapon axis sampled after ADS alignment/recoil/presence (v8)");
            }
        } catch (Throwable error) {
            failed = true;
            sample = null;
            System.err.println("[ViewpointGael] Physical weapon axis unavailable: " + error);
        }
    }

    static GaelSightProjection.Point current() {
        Sample value = sample;
        if (value == null || System.nanoTime() - value.at > 500_000_000L
                || !value.weapon.equals(ADS.P.weaponId)) return null;
        return value.point;
    }

    public static boolean ready() { return current() != null; }

    /**
     * Returns the direction of the rendered weapon axis in native world coordinates.
     * The direction includes the actual model pose, sight calibration, and ADS recoil.
     */
    public static boolean shotDirection(float facing, Vector3f result) {
        return shotDirection(facing, result, true);
    }

    /** Returns the ADS barrel direction, optionally leaving post-ADS HoldSway out. */
    public static boolean shotDirection(float facing, Vector3f result, boolean includeHoldSway) {
        return shotDirection(facing, result, includeHoldSway, true);
    }

    /** Optionally exclude the extra post-shot visual correction when measuring new barrel motion. */
    public static boolean shotDirection(float facing, Vector3f result,
                                         boolean includeHoldSway, boolean includeShotCarry) {
        if (result == null || !Float.isFinite(facing) || !ADS.P.valid || ADS.P.weaponId == null
                || !VP.firstPerson() || VP.freeCam()) return false;
        try {
            Scratch state = scratch.get();
            ReferenceAlignment alignment = referenceAlignment(ADS.P.weaponId);
            physicalDirection((Vector3f) Fields.direction.get(null), alignment.yaw,
                    alignment.pitch, alignment.roll, (Matrix4f) Fields.W.get(null),
                    (Matrix4f) Fields.M.get(null), state.direction, state.calibration);
            if (Fields.presence.getBoolean(null)) {
                Presence.fullCorrection().transformDirection(state.direction).normalize();
            }
            // HoldSway rotates the rendered arm/weapon bones after ADS solves its
            // reference axis. Mirror that exact live rotation into the shot ray.
            if (includeHoldSway) {
                if (includeShotCarry) HoldSway.applyToShotDirection(ADS.P.weaponId, state.direction);
                else HoldSway.applySwayToShotDirection(ADS.P.weaponId, state.direction);
            }
            ADS.cmsDirToRender(state.direction, facing, result);
            float length2 = result.lengthSquared();
            if (!Float.isFinite(length2) || length2 < 1.0e-8f) return false;
            result.normalize();
            return Float.isFinite(result.x) && Float.isFinite(result.y) && Float.isFinite(result.z);
        } catch (Throwable error) {
            return false;
        }
    }

    public static boolean gripPivot(IsoPlayer player, Matrix4f pose, Vector3f result) {
        if (player == null || player.primaryHandModel == null) return false;
        var model = player.primaryHandModel;
        if (model.attachmentNameSelf == null) return false;
        ModelAttachment grip = model.getAttachmentById(model.attachmentNameSelf);
        if (grip == null) return false;
        try {
            ((Matrix4f)Fields.W.get(null)).transformPosition(grip.getOffset(), result);
            pose.transformPosition(result);
            return Float.isFinite(result.x) && Float.isFinite(result.y) && Float.isFinite(result.z);
        } catch (ReflectiveOperationException error) { return false; }
    }

    /** Resolve the actual hand/prop joint when a Gael model has no self grip attachment. */
    public static boolean gripPivot(IsoPlayer player, Object animationPlayer, Matrix4f pose, Vector3f result) {
        if (gripPivot(player, pose, result)) return true;
        if (player == null || player.primaryHandModel == null || !(animationPlayer instanceof AnimationPlayer ap)) return false;
        try {
            String parentBone = player.primaryHandModel.parentBoneName;
            if (parentBone == null || parentBone.isEmpty()) return false;
            int index = ap.getSkinningBoneIndex(parentBone, -1);
            if (index < 0) return false;
            Scratch work = scratch.get();
            PZMath.convertMatrix(ap.getModelTransformAt(index), work.bone);
            work.bone.transpose().getTranslation(result);
            return Float.isFinite(result.x) && Float.isFinite(result.y) && Float.isFinite(result.z);
        } catch (Throwable error) {
            return false;
        }
    }

    static void physicalDirection(Vector3f calibrated, float yaw, float pitch, float roll,
                                  Matrix4f weapon, Matrix4f pose, Vector3f result, Quaternionf correction) {
        // ADS rotates its reference axis to calibrate the sights before solving
        // the weapon pose. Undo that reference adjustment, not the rendered pose.
        correction.identity().rotateZ((float)Math.toRadians(yaw))
                .rotateX((float)Math.toRadians(pitch)).rotateY((float)Math.toRadians(roll)).invert();
        correction.transform(result.set(calibrated));
        weapon.transformDirection(result);
        pose.transformDirection(result).normalize();
    }

    private static ReferenceAlignment referenceAlignment(String weaponId) {
        ReferenceAlignment value = referenceAlignment;
        if (value != null && weaponId.equals(value.weaponId)
                && System.nanoTime() - value.at <= 500_000_000L) return value;
        // Keep compatibility with older Lua bridges; the current bridge publishes
        // the stable saved values every frame, leaving animated offsets in the ray.
        return new ReferenceAlignment(weaponId, ADS.P.adjYaw, ADS.P.adjPitch, ADS.P.adjRoll, System.nanoTime());
    }

    private record Sample(GaelSightProjection.Point point, String weapon, long at) {}
    private record ReferenceAlignment(String weaponId, float yaw, float pitch, float roll, long at) {}
    private static final class Scratch {
        final Vector3f direction = new Vector3f(), render = new Vector3f();
        final Quaternionf calibration = new Quaternionf();
        final Matrix4f bone = new Matrix4f();
    }
    private GaelWeaponMotion() {}
}
