package viewpointgael;

import me.zed_0xff.zombie_buddy.Exposer;
import pvads.GaelBarrelRay;
import pvads.GaelDynamicProfile;
import pvads.GaelRecoilAim;
import pvads.GaelSightProjection;
import pvads.GaelWeaponMotion;
import pvads.GaelImpactMarker;
import pvads.GaelNativeShot;
import stgael.ballistics.BallisticProfile;
import stgael.pz.PzBallisticProfileCatalog;
import stgael.pz.PzBallisticRuntime;
import viewpoint.core.View;
import viewpoint.input.FreeCam;
import viewpoint.input.Look;
import viewpoint.render.MousePick;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;

@Exposer.LuaClass(name="ViewpointGael.Aim")
public final class AimProbe {
    public static volatile boolean suppressPose;

    static {
        try {
            Main.main(null);
        } catch (Throwable t) {
            System.err.println("[ViewpointGael] Bridge init error: " + t);
        }
    }

    public static void reinitBridge() {
        Main.main(null);
    }

    public static boolean looking() {
        return View.enabled && Look.captured && !FreeCam.active;
    }

    public static boolean isThirdPerson() {
        return View.thirdPerson;
    }

    public static void setSuppressPose(boolean bl) {
        suppressPose = bl;
    }

    public static boolean setHoldSway(String string, double d, double d2) {
        return HoldSway.set(string, d, d2);
    }

    public static boolean setWeaponMotion(String weapon, double yaw, double pitch, double roll) {
        return HoldSway.set(weapon,yaw,pitch,roll);
    }

    public static boolean setDynamicProfile(String string, double d, double d2, double d3, double d4, double d5, double d6, double d7) {
        return GaelDynamicProfile.set(string, d, d2, d3, d4, d5, d6, d7);
    }

    public static void setRecoilAim(String string, double d, double d2, boolean bl) {
        GaelRecoilAim.set(string, d, d2, bl);
    }

    public static double recoilScreenX(int n) {
        return GaelRecoilAim.screenOffset((IsoGameCharacter)IsoPlayer.players[0], false, n);
    }

    public static double recoilScreenY(int n) {
        return GaelRecoilAim.screenOffset((IsoGameCharacter)IsoPlayer.players[0], true, n);
    }

    public static double sightMarkerX() {
        GaelSightProjection.Point point = GaelSightProjection.current();
        return point == null ? Double.NaN : point.x();
    }

    public static double sightMarkerY() {
        GaelSightProjection.Point point = GaelSightProjection.current();
        return point == null ? Double.NaN : point.y();
    }

    public static int shotMirrorVersion() {
        // Version 12 removes only saved alignment from the physical axis and
        // preserves active recoil/hold offsets.
        return 12;
    }

    public static boolean weaponMotionReady() { return GaelWeaponMotion.ready(); }

    public static void setWeaponReferenceAlignment(String weapon, double yaw, double pitch, double roll) {
        GaelWeaponMotion.setReferenceAlignment(weapon, yaw, pitch, roll);
    }

    public static void setShotSeparationScale(double d) {
        GaelBarrelRay.setSeparationScale(d);
    }

    public static boolean setShotOrigin(String weapon, double x, double y, double z) {
        return GaelNativeShot.setShotOrigin(weapon, x, y, z);
    }

    public static void setShotMotionGain(double gain) {
        GaelNativeShot.setShotMotionGain(gain);
    }

    public static void setShotCentering(double amount, boolean aiming) {
        GaelNativeShot.setShotCentering(amount, aiming);
    }

    /** Override one PZ ammo category's independent projectile parameters. */
    public static void registerBallisticProfile(String ammoTypeKey, double muzzleVelocity,
                                                double gravity, double dragPerSecond,
                                                double maxDistance, double maxFlightSeconds) {
        PzBallisticProfileCatalog.register(ammoTypeKey, new BallisticProfile(muzzleVelocity,
                gravity, dragPerSecond, maxDistance, maxFlightSeconds));
    }

    public static double sightTargetDistance() {
        GaelSightProjection.Line line = GaelSightProjection.currentLine();
        return line == null ? Double.NaN : line.distance();
    }

    public static boolean impactVisible() { return GaelImpactMarker.visible(); }
    public static double impactScreenX() { return GaelImpactMarker.screenX(); }
    public static double impactScreenY() { return GaelImpactMarker.screenY(); }
    public static String impactLabel() { return GaelImpactMarker.label(); }

    public static int ballisticTrailCount() { return PzBallisticRuntime.diagnosticTrailCount(); }

    public static String ballisticTrailPath(int index) {
        return PzBallisticRuntime.diagnosticTrailPath(index);
    }

    public static Double aimX() {
        MousePick.Hit hit = AimProbe.fresh();
        return hit == null ? null : Double.valueOf(hit.x());
    }

    public static Double aimY() {
        MousePick.Hit hit = AimProbe.fresh();
        return hit == null ? null : Double.valueOf(hit.y());
    }

    public static Double aimZ() {
        MousePick.Hit hit = AimProbe.fresh();
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
