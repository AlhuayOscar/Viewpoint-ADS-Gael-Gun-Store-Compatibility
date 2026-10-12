package pvads;

import java.lang.reflect.Field;
import zombie.core.Core;
import zombie.characters.IsoPlayer;

/** Captures terminal points from optional Viewpoint True Ballistics and projects them for the HUD. */
public final class GaelImpactMarker {
    private static final ThreadLocal<double[]> PROJECTION = ThreadLocal.withInitial(() -> new double[2]);
    private static volatile double x, y, u;
    private static volatile double screenX = Double.NaN, screenY = Double.NaN;
    private static volatile double worldScreenX = Double.NaN, worldScreenY = Double.NaN;
    private static volatile String label = "";
    private static volatile long shotSequence = -1;
    private static volatile boolean hasImpact;

    private static volatile double camX, camY, camU, yaw, pitch, fov;
    private static volatile boolean cameraReady;

    public static void shotStarted(Object shooter, Object group, boolean test) {
        if (test || shooter == null || group == null) return;
        try {
            long seq = integer(field(group, "seq"));
            if (seq > shotSequence) {
                shotSequence = seq;
                hasImpact = false;
                screenX = screenY = Double.NaN;
                label = "Disparo " + seq + " en vuelo";
            }
        } catch (Throwable ignored) {}
    }

    public static void terminalImpact(Object manager, Object projectile) {
        try {
            if (!localRealShot(projectile)) return;
            if (bool(field(projectile, "alive"))) return; // penetrating rounds have not ended yet
            Object position = field(projectile, "position");
            Object result = field(manager, "res");
            long seq = integer(field(projectile, "shotSeq"));
            if (seq < shotSequence) return;
            int kind = (int) number(field(result, "kind"));
            String type;
            if (kind == 2) {
                Object who = field(result, "character");
                type = who == null ? "PERSONA" : (invokeBoolean(who, "isZombie") ? "ZOMBIE" : "PERSONA");
            } else if (kind == 3) {
                type = "VEHÍCULO";
            } else if (kind == 1) {
                Object world = field(result, "world");
                type = worldLabel((int) number(field(world, "kind")));
            } else {
                type = "IMPACTO";
            }
            save(position, seq, "Impacto: " + type);
        } catch (Throwable ignored) {}
    }

    public static void expired(Object projectile) {
        try {
            if (!localRealShot(projectile)) return;
            long seq = integer(field(projectile, "shotSeq"));
            if (seq < shotSequence) return;
            save(field(projectile, "position"), seq, "Fin de alcance / vuelo");
        } catch (Throwable ignored) {}
    }

    public static void worldImpact(Object projectile, Object point, int kind) {
        try {
            if (!localRealShot(projectile)) return;
            long seq = integer(field(projectile, "shotSeq"));
            if (seq < shotSequence) return;
            save(point, seq, "Impacto: " + worldLabel(kind));
        } catch (Throwable ignored) {}
    }

    /** Called after Viewpoint snapshots its camera for the frame. */
    public static void captureCamera(Object frame) {
        try {
            Class<?> look = Class.forName("viewpoint.input.Look");
            Class<?> view = Class.forName("viewpoint.core.View");
            double cX = number(field(frame, "camX")) - number(field(frame, "eyeX"));
            double cY = number(field(frame, "camY")) - number(field(frame, "eyeZ"));
            double cU = number(field(frame, "camZ")) * 2.449489742783178 + number(field(frame, "eyeY"));
            boolean third = staticBoolean("viewpoint.input.ThirdPerson", "active");
            if (staticBoolean("viewpoint.input.FreeCam", "active")) { cameraReady = false; return; }
            if (third) {
                cX += staticNumber("viewpoint.input.ThirdPerson", "offsetX");
                cY += staticNumber("viewpoint.input.ThirdPerson", "offsetY");
                cU += staticNumber("viewpoint.input.ThirdPerson", "offsetUp");
            }
            camX = cX; camY = cY; camU = cU;
            yaw = number(look.getField("yaw").get(null));
            pitch = number(look.getField("pitch").get(null));
            fov = (double) view.getMethod("fovY", boolean.class).invoke(null, third);
            cameraReady = Double.isFinite(fov) && fov > 0.01 && fov < 3.1;
        } catch (Throwable ignored) { cameraReady = false; }
    }

    private static void save(Object point, long seq, String what) throws Exception {
        if (seq < shotSequence) return;
        double px = number(field(point, "x")), py = number(field(point, "y")), pu = number(field(point, "u"));
        if (!Double.isFinite(px) || !Double.isFinite(py) || !Double.isFinite(pu)) return;
        x = px; y = py; u = pu; shotSequence = seq;
        hasImpact = true;
        label = what + "  (X " + fmt(px) + ", Y " + fmt(py) + " tiles; altura " + fmt(pu) + " m)";
        project();
    }

    private static boolean localRealShot(Object projectile) throws Exception {
        Object group = field(projectile, "group");
        if (group == null || bool(field(group, "test"))) return false;
        return field(group, "shooter") == IsoPlayer.players[0];
    }

    private static void project() {
        double[] point = projectPoint(x, y, u);
        screenX = point[0]; screenY = point[1];
    }

    /** Projects a launcher impact using the active Viewpoint camera, independent of the firearm marker. */
    public static void projectWorldPoint(double worldX, double worldY, double worldU) {
        double[] point = projectPoint(worldX, worldY, worldU);
        worldScreenX = point[0]; worldScreenY = point[1];
    }

    private static double[] projectPoint(double worldX, double worldY, double worldU) {
        double[] point = PROJECTION.get();
        if (!cameraReady) { point[0] = point[1] = Double.NaN; return point; }
        double dx = worldX - camX, dy = worldY - camY, dz = worldU - camU;
        double cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
        double depth = dx * cy * cp + dy * sy * cp + dz * sp;
        if (depth <= 0.02) { point[0] = point[1] = Double.NaN; return point; }
        double right = -dx * sy + dy * cy;
        double up = -dx * cy * sp - dy * sy * sp + dz * cp;
        double height = Core.getInstance().getScreenHeight();
        double focal = height / (2.0 * Math.tan(fov / 2.0));
        point[0] = Core.getInstance().getScreenWidth() * 0.5 + right / depth * focal;
        point[1] = height * 0.5 - up / depth * focal;
        return point;
    }

    public static boolean worldPointVisible() {
        return Double.isFinite(worldScreenX) && Double.isFinite(worldScreenY)
                && worldScreenX >= 0 && worldScreenY >= 0
                && worldScreenX < Core.getInstance().getScreenWidth()
                && worldScreenY < Core.getInstance().getScreenHeight();
    }
    public static double worldPointScreenX() { return worldScreenX; }
    public static double worldPointScreenY() { return worldScreenY; }

    public static boolean visible() {
        project();
        return hasImpact && shotSequence >= 0 && Double.isFinite(screenX) && Double.isFinite(screenY)
                && screenX >= 0 && screenY >= 0
                && screenX < Core.getInstance().getScreenWidth() && screenY < Core.getInstance().getScreenHeight();
    }
    public static double screenX() { project(); return screenX; }
    public static double screenY() { project(); return screenY; }
    public static String label() { return label; }

    private static String worldLabel(int kind) {
        return switch (kind) {
            case 1 -> "PARED / PUERTA"; case 2 -> "VALLA / MURO BAJO";
            case 3 -> "SUELO"; case 4 -> "TECHO"; case 5 -> "ÁRBOL";
            case 6 -> "MUEBLE"; case 7 -> "BORDE DEL MAPA"; default -> "MUNDO";
        };
    }
    private static String fmt(double n) { return String.format(java.util.Locale.ROOT, "%.2f", n); }
    private static Object field(Object target, String name) throws Exception {
        Field f = target.getClass().getField(name);
        return f.get(target);
    }
    private static double number(Object value) { return ((Number) value).doubleValue(); }
    private static long integer(Object value) { return ((Number) value).longValue(); }
    private static boolean bool(Object value) { return (Boolean) value; }
    private static boolean invokeBoolean(Object target, String name) {
        try { return (Boolean) target.getClass().getMethod(name).invoke(target); }
        catch (Throwable ignored) { return false; }
    }
    private static boolean staticBoolean(String type, String name) throws Exception {
        return Class.forName(type).getField(name).getBoolean(null);
    }
    private static double staticNumber(String type, String name) throws Exception {
        return number(Class.forName(type).getField(name).get(null));
    }
    private GaelImpactMarker() {}
}
