package viewpointgael;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;

/** Small procedural rotation of the held gun and arms after ADS has solved its calibrated pose. */
public final class HoldSway {
    private static final float LIMIT = 25f;
    private static final float POST_ALIGNMENT_FOLLOW_THROUGH = 0.25f;
    private static final long MAX_AGE_NS = 500_000_000L;
    private static volatile State state;
    private static boolean reported;
    private static boolean failed;

    private record State(String weaponId, float yaw, float pitch, long at) {}

    private static final class Scratch {
        final Vector3f pivot = new Vector3f();
        final Vector3f right = new Vector3f();
        final Matrix4f rotation = new Matrix4f();
    }

    private static final ThreadLocal<Scratch> scratch = ThreadLocal.withInitial(Scratch::new);

    static boolean set(String weaponId, double yaw, double pitch) {
        if (weaponId == null || !Double.isFinite(yaw) || !Double.isFinite(pitch)) return false;
        state = new State(weaponId,
                (float) Math.max(-LIMIT, Math.min(LIMIT, yaw)),
                (float) Math.max(-LIMIT, Math.min(LIMIT, pitch)), System.nanoTime());
        return true;
    }

    public static void apply(Vector3f eye, Vector3f direction, float progress, Matrix4f pose) {
        State current = state;
        if (failed || current == null || System.nanoTime() - current.at > MAX_AGE_NS
                || progress <= 0f || (current.yaw == 0f && current.pitch == 0f)) return;
        try {
            IsoPlayer player = IsoPlayer.players[0];
            InventoryItem weapon = player == null ? null : player.getPrimaryHandItem();
            if (weapon == null || !current.weaponId.equals(weapon.getFullType())) return;
            rotatePose(eye, direction, current.yaw * POST_ALIGNMENT_FOLLOW_THROUGH,
                    current.pitch * POST_ALIGNMENT_FOLLOW_THROUGH, progress, pose);
            if (!reported) {
                reported = true;
                System.out.println("[ViewpointGael] post-alignment hold sway active for " + current.weaponId);
            }
        } catch (RuntimeException ex) {
            failed = true;
            System.err.println("[ViewpointGael] post-alignment hold sway disabled: " + ex);
        }
    }

    static void rotatePose(Vector3f eye, Vector3f direction, float yaw, float pitch,
                           float progress, Matrix4f pose) {
        Scratch s = scratch.get();
        s.right.set(direction).cross(0f, 1f, 0f);
        if (s.right.lengthSquared() < 1e-6f) s.right.set(1f, 0f, 0f);
        else s.right.normalize();
        // A fixed rear pivot translates the entire sight too far during a
        // long automatic burst. Keep the barrel angle, but shorten that lever
        // as the angle grows so the weapon stays close to its ADS position.
        float largestAngle = Math.max(Math.abs(yaw), Math.abs(pitch));
        float pivotBack = 0.20f * Math.min(1f, 8f / Math.max(8f, largestAngle));
        s.pivot.set(eye).fma(-pivotBack, direction);
        float fade = Math.min(1f, progress);
        s.rotation.identity().translate(s.pivot)
                .rotate((float) Math.toRadians(yaw * fade), 0f, 1f, 0f)
                .rotate((float) Math.toRadians(pitch * fade), s.right.x, s.right.y, s.right.z)
                .translate(-s.pivot.x, -s.pivot.y, -s.pivot.z)
                .mul(pose, pose);
    }

    private HoldSway() {}
}
