package pvads;

import zombie.characters.IsoPlayer;
import zombie.core.Core;

/** Carries the rendered ADS weapon-axis deviation into the shot and impact HUD. */
public final class GaelBarrelRay {
    private static volatile double separationScale = 1.0;

    public static void setSeparationScale(double value) {
        if (Double.isFinite(value)) separationScale = Math.max(0, Math.min(10, value));
    }

    public static boolean replace(double[] ray) {
        if (!VP.firstPerson() || VP.freeCam()) return false;
        IsoPlayer player = IsoPlayer.players[0];
        if (player == null || !player.isAiming()) return false;
        Core core = Core.getInstance();
        GaelSightProjection.Point physical = GaelWeaponMotion.current();
        if (physical == null) return false;
        return fromScreen(ray, physical.x(), physical.y(), core.getScreenWidth(),
                core.getScreenHeight(), ADS.fovOutRad, VP.yaw(), VP.pitch());
    }

    static boolean fromScreen(double[] ray, double x, double y, int width, int height,
                              double fov, double yaw, double pitch) {
        if (ray == null || ray.length < 7 || width <= 0 || height <= 0
                || !Double.isFinite(x) || !Double.isFinite(y) || x == -9999 || y == -9999
                || !Double.isFinite(yaw) || !Double.isFinite(pitch)
                || !Double.isFinite(fov) || fov <= 0 || fov >= 3.1) return false;
        double focal = height / (2 * Math.tan(fov / 2));
        // Start at the fixed screen center. Only the rendered angular deviation
        // drives the endpoint; projected weapon position (ovWin) is irrelevant.
        double centerX = width * 0.5, centerY = height * 0.5;
        // Carry the weapon's visible angular deviation from the reticle centre to the shot
        // in the same direction. A previous subtraction mirrored the bullet away from the gun.
        double multiplier = separationScale;
        double targetX = centerX + multiplier * (x - centerX);
        double targetY = centerY + multiplier * (y - centerY);
        double horizontal = (targetX - width * 0.5) / focal;
        double vertical = (height * 0.5 - targetY) / focal;
        double cy = Math.cos(yaw), sy = Math.sin(yaw);
        double cp = Math.cos(pitch), sp = Math.sin(pitch);
        double dx = cy * cp - sy * horizontal - cy * sp * vertical;
        double dy = sy * cp + cy * horizontal - sy * sp * vertical;
        double dz = sp + cp * vertical;
        double length = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (!Double.isFinite(length) || length < 1e-6) return false;
        ray[3] = dx / length;
        ray[4] = dy / length;
        ray[5] = dz / length;
        return true;
    }

    // Kept for the test/diagnostic API. The ray now uses the measured deviation 1:1.
    static double angularGain(double angleDegrees) {
        return Double.isFinite(angleDegrees) ? 1.0 : Double.NaN;
    }

    private GaelBarrelRay() {}
}
