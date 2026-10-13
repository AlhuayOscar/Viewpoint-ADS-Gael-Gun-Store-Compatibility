package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.iso.Vector3;
import zombie.scripting.objects.ModelAttachment;
import zombie.scripting.objects.ModelAttachmentId;

/** Replaces the ADS sight ray with the raised model's physical muzzle ray when available. */
public final class GaelBarrelRay {
    private static volatile double separationScale = 1.0;
    private static volatile long lastPatchLogNs;
    private static final class Scratch {
        final Vector3 muzzle = new Vector3();
        final Vector3 direction = new Vector3();
    }

    private static final ThreadLocal<Scratch> scratch = ThreadLocal.withInitial(Scratch::new);

    public static void setSeparationScale(double scale) {
        if (Double.isFinite(scale)) separationScale = Math.max(0, Math.min(3, scale));
    }

    public static boolean replace(double[] ray) {
        if (ray == null || ray.length < 7 || !VP.firstPerson() || VP.freeCam()) return false;
        IsoPlayer player = IsoPlayer.players[0];
        if (player == null || !player.isAiming()) return false;
        ModelInstance model = player.primaryHandModel;
        if (model == null || model.modelScript == null || model.animPlayer == null) return false;
        ModelAttachment attachment = model.modelScript.getAttachmentById(ModelAttachmentId.MUZZLE);
        if (attachment == null) return false;

        Scratch s = scratch.get();
        model.getAttachmentWorldPosition(attachment, s.muzzle, s.direction);
        double ox = s.muzzle.x, oy = s.muzzle.y, ou = s.muzzle.z * VP.SQRT6;
        double dx = s.direction.x, dy = s.direction.y, du = s.direction.z * VP.SQRT6;
        double length = Math.sqrt(dx * dx + dy * dy + du * du);
        double feet = player.getZ() * VP.SQRT6;
        double offX = ox - player.getX(), offY = oy - player.getY();
        if (!finite(ox, oy, ou, dx, dy, du) || length < 1e-6
                || offX * offX + offY * offY > 1.6 * 1.6
                || ou - feet < 0.2 || ou - feet > 2.3) return false;
        dx /= length; dy /= length; du /= length;
        if (dx * ray[3] + dy * ray[4] + du * ray[5] < 0.2) return false;
        // The model's muzzle direction already points opposite the visible
        // sight displacement. Earlier reflecting it a second time put the
        // shot marker back on the front post. Extrapolate the muzzle ray away
        // from the calibrated camera axis instead, using the same ray for
        // ballistics and the HUD marker.
        double yaw = VP.yaw(), pitch = VP.pitch();
        double cp = Math.cos(pitch);
        double bx = Math.cos(yaw) * cp;
        double by = Math.sin(yaw) * cp;
        double bu = Math.sin(pitch);
        double dot = dx * bx + dy * by + du * bu;
        if (!finite(bx, by, bu, dot) || dot < 0.35) return false;
        ray[0] = ox; ray[1] = oy; ray[2] = ou;
        separatedDirection(ray, dx, dy, du, bx, by, bu, dot);
        return true;
    }

    public static void logPatchResult(double[] ray, boolean valid, boolean replaced) {
        long now = System.nanoTime();
        if (now - lastPatchLogNs < 1_000_000_000L) return;
        lastPatchLogNs = now;
        String origin = ray != null && ray.length >= 3
                ? String.format("(%.2f,%.2f,%.2f)", ray[0], ray[1], ray[2]) : "unavailable";
        String direction = ray != null && ray.length >= 6
                ? String.format("(%.3f,%.3f,%.3f)", ray[3], ray[4], ray[5]) : "unavailable";
        System.out.println("[ViewpointGaelCompat][barrel-ray] valid=" + valid
                + " replaced=" + replaced + " origin=" + origin + " dir=" + direction);
    }

    static void separatedDirection(double[] out, double dx, double dy, double du,
                                   double bx, double by, double bu, double dot) {
        double errorDegrees = Math.toDegrees(Math.acos(Math.max(-1, Math.min(1, dot))));
        double t = Math.max(0, Math.min(1, (errorDegrees - 1.0) / 9.0));
        double gain = (1.0 + t * t * (3.0 - 2.0 * t)) * separationScale;
        double mx = dot * bx + gain * (dx - dot * bx);
        double my = dot * by + gain * (dy - dot * by);
        double mu = dot * bu + gain * (du - dot * bu);
        double invLength = 1.0 / Math.sqrt(mx * mx + my * my + mu * mu);
        out[3] = mx * invLength;
        out[4] = my * invLength;
        out[5] = mu * invLength;
    }

    private static boolean finite(double... values) {
        for (double value : values) if (!Double.isFinite(value)) return false;
        return true;
    }

    private GaelBarrelRay() {}
}
