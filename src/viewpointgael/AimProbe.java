package viewpointgael;

import me.zed_0xff.zombie_buddy.Exposer;
import viewpoint.core.View;
import viewpoint.input.FreeCam;
import viewpoint.input.Look;
import viewpoint.render.MousePick;

/**
 * Aim probe and optional procedural hold-sway control.
 * Lua uses it to tell a captured Viewpoint view from the isometric camera.
 * The aim point is the same screen-center depth hit CrosshairAim uses, in tile coordinates.
 * aimZ is a floor coordinate; Gael archery multiplies it by 2.44949 to get its height unit.
 */
@Exposer.LuaClass(name = "ViewpointGael.Aim")
public final class AimProbe {
    public static volatile boolean suppressPose;

    public static boolean looking() {
        return View.enabled && Look.captured && !FreeCam.active;
    }

    public static void setSuppressPose(boolean suppress) {
        suppressPose = suppress;
    }

    /** Animate the post-alignment pose; never mutate the calibrated ADS profile. */
    public static boolean setHoldSway(String weaponId, double yaw, double pitch) {
        return HoldSway.set(weaponId, yaw, pitch);
    }

    /** Dynamic ADS motion must not reset the profile's model measurements every frame. */
    public static boolean setDynamicProfile(String weaponId, double x, double y, double z,
                                            double pitch, double yaw, double roll, double fov) {
        return pvads.GaelDynamicProfile.set(weaponId, x, y, z, pitch, yaw, roll, fov);
    }

    public static void setRecoilAim(String weaponId, double yaw, double pitch, boolean enabled) {
        pvads.GaelRecoilAim.set(weaponId, yaw, pitch, enabled);
    }

    public static double recoilScreenX(int viewportHeight) {
        return pvads.GaelRecoilAim.screenOffset(zombie.characters.IsoPlayer.players[0], false, viewportHeight);
    }

    public static double recoilScreenY(int viewportHeight) {
        return pvads.GaelRecoilAim.screenOffset(zombie.characters.IsoPlayer.players[0], true, viewportHeight);
    }

    /** Screen direction of the live barrel ray; NaN means use PVADS' sight dot. */
    public static double sightMarkerX() {
        pvads.GaelSightProjection.Point point = pvads.GaelSightProjection.current();
        return point == null ? Double.NaN : point.x();
    }

    public static double sightMarkerY() {
        pvads.GaelSightProjection.Point point = pvads.GaelSightProjection.current();
        return point == null ? Double.NaN : point.y();
    }

    /** Lets Lua reload distinguish the mirrored ballistic ray from older loaded JARs. */
    public static int shotMirrorVersion() {
        return 2;
    }

    public static void setShotSeparationScale(double scale) {
        pvads.GaelBarrelRay.setSeparationScale(scale);
    }

    /** Called by the OnHitZombie event before the game's damage calculation. */
    public static boolean markHeadshot(zombie.characters.IsoGameCharacter target,
                                       zombie.characters.IsoGameCharacter attacker,
                                       zombie.inventory.types.HandWeapon weapon,
                                       boolean headHit) {
        return RangeBalance.markHeadshot(target, attacker, weapon, headHit);
    }

    public static double sightTargetDistance() {
        pvads.GaelSightProjection.Line line = pvads.GaelSightProjection.currentLine();
        return line == null ? Double.NaN : line.distance();
    }

    public static Double aimX() {
        MousePick.Hit hit = fresh();
        return hit == null ? null : Double.valueOf(hit.x());
    }

    public static Double aimY() {
        MousePick.Hit hit = fresh();
        return hit == null ? null : Double.valueOf(hit.y());
    }

    public static Double aimZ() {
        MousePick.Hit hit = fresh();
        return hit == null ? null : Double.valueOf(hit.z());
    }

    public static float yaw() {
        return Look.yaw;
    }

    public static float pitch() {
        return Look.pitch;
    }

    private static MousePick.Hit fresh() {
        MousePick.Hit hit = MousePick.aimHit;
        MousePick.Ask ask = MousePick.aim;
        if (hit == null || ask == null || hit.ask() != ask) {
            return null;
        }
        return hit;
    }

    private AimProbe() {
    }
}
