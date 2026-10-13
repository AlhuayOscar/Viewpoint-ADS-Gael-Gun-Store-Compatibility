package pvads;

import viewpointgael.AimProbe;
import zombie.characters.IsoPlayer;
import zombie.core.Core;

/** Projects the barrel direction; depth is used only to show accumulated lateral miss. */
public final class GaelSightProjection {
    private static final double DEFAULT_DEPTH = 60.0;
    private static final double MIN_DEPTH = 2.0;
    private static final double MAX_DEPTH = 150.0;
    private static final long HUD_SAMPLE_NS = 4_000_000L;
    private static volatile Line lastLine;
    private static volatile long lastSampleNs;

    public record Point(double x, double y) {}
    public record Line(Point end, double distance) {}

    public static Point current() {
        Line line = currentLine();
        return line == null ? null : line.end();
    }

    public static Line currentLine() {
        long now = System.nanoTime();
        if (now - lastSampleNs < HUD_SAMPLE_NS) return lastLine;
        Line line = sampleLine();
        lastLine = line;
        lastSampleNs = now;
        return line;
    }

    private static Line sampleLine() {
        double[] sight = new double[7];
        if (!Sight.ray(sight) || !VP.firstPerson() || VP.freeCam()) return null;
        Core core = Core.getInstance();
        if (core == null) return null;
        int width = core.getScreenWidth(), height = core.getScreenHeight();
        float fov = ADS.fovOutRad;
        if (width <= 0 || height <= 0 || !Float.isFinite(fov)
                || fov <= 0.1f || fov >= 3.1f) return null;

        double yaw = VP.yaw(), pitch = VP.pitch();
        Point end = project(0, 0, 0, -sight[3], sight[5], -sight[4],
                yaw, pitch, fov, width, height, DEFAULT_DEPTH);
        if (end == null) return null;

        double distance = DEFAULT_DEPTH;
        IsoPlayer player = IsoPlayer.players[0];
        Double hitX = AimProbe.aimX(), hitY = AimProbe.aimY(), hitZ = AimProbe.aimZ();
        if (player != null && hitX != null && hitY != null && hitZ != null
                && finite(hitX, hitY, hitZ)) {
            double hx = hitX - player.getX(), hy = hitY - player.getY();
            double hz = (hitZ - player.getZ()) * VP.SQRT6;
            double range = Math.sqrt(hx * hx + hy * hy + hz * hz);
            if (Double.isFinite(range) && range > 0.1)
                distance = Math.max(MIN_DEPTH, Math.min(MAX_DEPTH, range));
        }
        return new Line(end, distance);
    }

    static Point project(double ox, double oy, double oz, double dx, double dy, double dz,
                         double yaw, double pitch, double fov, int width, int height,
                         double depth) {
        if (!finite(ox, oy, oz, dx, dy, dz, yaw, pitch, fov, depth)
                || width <= 0 || height <= 0 || depth < MIN_DEPTH) return null;
        double cp = Math.cos(pitch);
        double fx = -Math.cos(yaw) * cp, fy = Math.sin(pitch), fz = -Math.sin(yaw) * cp;
        double rightLength = Math.hypot(fx, fz);
        if (rightLength < 1e-6) return null;
        double rx = -fz / rightLength, rz = fx / rightLength;
        // Match PVADS' cross products: right = forward x world-up;
        // up = right x forward.
        double ux = -rz * fy, uy = rz * fx - rx * fz, uz = rx * fy;
        double along = dx * fx + dy * fy + dz * fz;
        if (along <= 0.1) return null;
        double originDepth = ox * fx + oy * fy + oz * fz;
        double t = (depth - originDepth) / along;
        if (t <= 0) return null;
        double px = ox + t * dx, py = oy + t * dy, pz = oz + t * dz;
        double focal = height / (2.0 * Math.tan(fov * 0.5));
        double screenX = width * 0.5 + (px * rx + pz * rz) * focal / depth;
        double screenY = height * 0.5 - (px * ux + py * uy + pz * uz) * focal / depth;
        return finite(screenX, screenY) ? new Point(screenX, screenY) : null;
    }

    private static boolean finite(double... values) {
        for (double value : values) if (!Double.isFinite(value)) return false;
        return true;
    }

    private GaelSightProjection() {}
}
