package pvads;

import viewpoint.core.View;
import viewpoint.input.FreeCam;
import viewpoint.input.Look;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.inventory.InventoryItem;
import java.lang.reflect.Field;

/** Keeps Gael's procedural recoil aim and HUD marker on the same angular offset. */
public final class GaelRecoilAim {
    private static final long MAX_AGE_NS = 150_000_000L;
    private static final float MAX_ANGLE = 45f;
    /** Lua publishes the exact inverse of the visible barrel angle for the shot ray. */
    private static final float PROJECTILE_RECOIL_MULTIPLIER = 1.0f;
    private static volatile State state;
    private static volatile Field solutionDirectionField;
    private static volatile Field directionXField;
    private static volatile Field directionYField;
    private static volatile Field directionUField;
    private static volatile long lastShotDirectionLogNs;

    private record State(String weaponId, float yaw, float pitch, long at) {}

    public static void set(String weaponId, double yaw, double pitch, boolean enabled) {
        if (!enabled || weaponId == null || !Double.isFinite(yaw) || !Double.isFinite(pitch)) {
            state = null;
            return;
        }
        state = new State(weaponId,
                (float) Math.max(-MAX_ANGLE, Math.min(MAX_ANGLE, yaw)),
                (float) Math.max(-MAX_ANGLE, Math.min(MAX_ANGLE, pitch)), System.nanoTime());
    }

    private static State current(IsoGameCharacter character) {
        State value = state;
        if (value == null || character == null || character != IsoPlayer.players[0]
                || !character.isAiming() || !View.enabled
                || !Look.captured || FreeCam.active || ADS.eShared < 0.85f
                || System.nanoTime() - value.at > MAX_AGE_NS) return null;
        InventoryItem weapon = character.getPrimaryHandItem();
        return weapon != null && value.weaponId.equals(weapon.getFullType()) ? value : null;
    }

    public static float yaw(IsoGameCharacter character, float base) {
        State value = current(character);
        return value == null ? base : base + (float) Math.toRadians(value.yaw);
    }

    public static float pitch(IsoGameCharacter character, float base) {
        State value = current(character);
        return value == null ? base : base + (float) Math.toRadians(value.pitch);
    }

    /** Adjust the final direction True Ballistics will copy into its projectile. */
    public static void onShotSolution(IsoGameCharacter character, Object solution, boolean valid) {
        if (!valid) {
            logShotDirectionSkip(character, "invalid-aim-solution");
            return;
        }
        applyToShotSolution(character, solution);
    }

    public static boolean applyToShotSolution(IsoGameCharacter character, Object solution) {
        State value = current(character);
        if (solution == null) {
            logShotDirectionSkip(character, "missing-solution");
            return false;
        }
        if (value == null) {
            logShotDirectionSkip(character, "aim-state-unavailable");
            return false;
        }
        try {
            Field directionField = solutionDirectionField;
            if (directionField == null) {
                directionField = solution.getClass().getField("direction");
                solutionDirectionField = directionField;
            }
            Object direction = directionField.get(solution);
            if (direction == null) return false;
            Field xField = directionXField;
            Field yField = directionYField;
            Field uField = directionUField;
            if (xField == null || yField == null || uField == null) {
                Class<?> type = direction.getClass();
                xField = type.getField("x");
                yField = type.getField("y");
                uField = type.getField("u");
                directionXField = xField;
                directionYField = yField;
                directionUField = uField;
            }
            double x = xField.getDouble(direction);
            double y = yField.getDouble(direction);
            double u = uField.getDouble(direction);
            double horizontal = Math.hypot(x, y);
            if (!Double.isFinite(x) || !Double.isFinite(y) || !Double.isFinite(u)
                    || horizontal < 1.0e-8) return false;
            double baseYaw = Math.atan2(y, x);
            double basePitch = Math.atan2(u, horizontal);
            double yaw = baseYaw + Math.toRadians(value.yaw * PROJECTILE_RECOIL_MULTIPLIER);
            double pitch = basePitch + Math.toRadians(value.pitch * PROJECTILE_RECOIL_MULTIPLIER);
            double cosPitch = Math.cos(pitch);
            xField.setDouble(direction, Math.cos(yaw) * cosPitch);
            yField.setDouble(direction, Math.sin(yaw) * cosPitch);
            uField.setDouble(direction, Math.sin(pitch));
            long now = System.nanoTime();
            if (now - lastShotDirectionLogNs >= 1_000_000_000L) {
                lastShotDirectionLogNs = now;
                System.out.println("[ViewpointGaelCompat][vtb-shot-direction] weapon=" + value.weaponId
                        + " inputYaw=" + String.format("%.2f", Math.toDegrees(baseYaw))
                        + " inputPitch=" + String.format("%.2f", Math.toDegrees(basePitch))
                        + " recoilYaw=" + String.format("%.2f", value.yaw)
                        + " recoilPitch=" + String.format("%.2f", value.pitch)
                        + " multiplier=" + String.format("%.2f", PROJECTILE_RECOIL_MULTIPLIER)
                        + " outputYaw=" + String.format("%.2f", Math.toDegrees(yaw))
                        + " outputPitch=" + String.format("%.2f", Math.toDegrees(pitch)));
            }
            return true;
        } catch (ReflectiveOperationException | RuntimeException error) {
            System.out.println("[ViewpointGaelCompat][vtb-shot-direction-error] "
                    + error.getClass().getSimpleName() + ": " + error.getMessage());
            return false;
        }
    }

    private static void logShotDirectionSkip(IsoGameCharacter character, String reason) {
        long now = System.nanoTime();
        if (now - lastShotDirectionLogNs >= 1_000_000_000L) {
            lastShotDirectionLogNs = now;
            System.out.println("[ViewpointGaelCompat][vtb-shot-direction-skip] reason=" + reason
                    + " character=" + (character == null ? "null" : character.getClass().getSimpleName())
                    + " aiming=" + (character != null && character.isAiming())
                    + " view=" + View.enabled + " captured=" + Look.captured
                    + " freecam=" + FreeCam.active + " ads=" + String.format("%.2f", ADS.eShared));
        }
    }

    /** Apply the live recoil to the final ADS ray after True Ballistics obtains it. */
    public static boolean applyOffsetToSightRay(double[] ray) {
        IsoPlayer player = IsoPlayer.players[0];
        State value = current(player);
        if (value == null || ray == null || ray.length < 6
                || !Double.isFinite(ray[3]) || !Double.isFinite(ray[4]) || !Double.isFinite(ray[5])) {
            return false;
        }
        double horizontal = Math.hypot(ray[3], ray[4]);
        if (horizontal < 1.0e-8) return false;
        double appliedYaw = value.yaw * PROJECTILE_RECOIL_MULTIPLIER;
        double appliedPitch = value.pitch * PROJECTILE_RECOIL_MULTIPLIER;
        double yaw = Math.atan2(ray[4], ray[3]) + Math.toRadians(appliedYaw);
        double pitch = Math.atan2(ray[5], horizontal) + Math.toRadians(appliedPitch);
        double cosPitch = Math.cos(pitch);
        ray[3] = Math.cos(yaw) * cosPitch;
        ray[4] = Math.sin(yaw) * cosPitch;
        ray[5] = Math.sin(pitch);
        long now = System.nanoTime();
        if (now - lastSightRayLogNs >= 1_000_000_000L) {
            lastSightRayLogNs = now;
            System.out.println("[ViewpointGaelCompat][vtb-sight-ray] weapon=" + value.weaponId
                    + " offsetYaw=" + String.format("%.2f", appliedYaw)
                    + " offsetPitch=" + String.format("%.2f", appliedPitch)
                    + " projectileMult=" + String.format("%.2f", PROJECTILE_RECOIL_MULTIPLIER)
                    + " outputYaw=" + String.format("%.2f", Math.toDegrees(yaw))
                    + " outputPitch=" + String.format("%.2f", Math.toDegrees(pitch)));
        }
        return true;
    }

    private static volatile long lastSightRayLogNs;

    public static void logSightRaySkipped(double[] ray, boolean valid) {
        long now = System.nanoTime();
        if (now - lastSightRaySkipLogNs >= 1_000_000_000L) {
            lastSightRaySkipLogNs = now;
            String direction = ray != null && ray.length >= 6
                    ? String.format("(%.3f,%.3f,%.3f)", ray[3], ray[4], ray[5]) : "unavailable";
            System.out.println("[ViewpointGaelCompat][vtb-sight-ray-skip] valid=" + valid
                    + " dir=" + direction + " reason=" + (valid ? "aim-state-gate-or-stale" : "ads-ray-invalid"));
        }
    }

    private static volatile long lastSightRaySkipLogNs;

    /** Make the True Ballistics ray use the same live Pitch/Yaw as CrosshairAim. */
    public static boolean applyShotDirection(IsoGameCharacter character, double baseYaw,
                                             double basePitch, double[] ray) {
        State value = current(character);
        if (value == null || ray == null || ray.length < 6
                || !Double.isFinite(baseYaw) || !Double.isFinite(basePitch)) return false;
        double yaw = baseYaw + Math.toRadians(value.yaw);
        double pitch = basePitch + Math.toRadians(value.pitch);
        double cosPitch = Math.cos(pitch);
        ray[3] = Math.cos(yaw) * cosPitch;
        ray[4] = Math.sin(yaw) * cosPitch;
        ray[5] = Math.sin(pitch);
        long now = System.nanoTime();
        if (now - lastShotRayLogNs >= 1_000_000_000L) {
            lastShotRayLogNs = now;
            System.out.println("[ViewpointGaelCompat][barrel-ray] weapon=" + value.weaponId
                    + " yaw=" + String.format("%.2f", Math.toDegrees(yaw - baseYaw))
                    + " pitch=" + String.format("%.2f", Math.toDegrees(pitch - basePitch)));
        }
        return true;
    }

    private static volatile long lastShotRayLogNs;

    /** Pixel displacement of the same angular offset used by CrosshairAim. */
    public static double screenOffset(IsoGameCharacter character, boolean vertical, int viewportHeight) {
        State value = current(character);
        if (value == null || viewportHeight <= 0) return 0;
        float fov = ADS.fovOutRad;
        if (!(fov > 0.1f && fov < 3.1f)) return 0;
        float degrees = vertical ? value.pitch : value.yaw;
        double pixels = Math.tan(Math.toRadians(degrees)) * viewportHeight
                / (2.0 * Math.tan(fov * 0.5f));
        return vertical ? -pixels : pixels;
    }

    private GaelRecoilAim() {}
}
