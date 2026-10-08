package viewpointgael;

import me.zed_0xff.zombie_buddy.Exposer;
import viewpoint.core.View;
import viewpoint.input.FreeCam;
import viewpoint.input.Look;
import viewpoint.render.MousePick;
import java.lang.reflect.Field;

/**
 * Read-only probe. Lua uses it to tell a captured Viewpoint view from the isometric camera.
 * The aim point is the same screen-center depth hit CrosshairAim uses, in tile coordinates.
 * aimZ is a floor coordinate; Gael archery multiplies it by 2.44949 to get its height unit.
 */
@Exposer.LuaClass(name = "ViewpointGael.Aim")
public final class AimProbe {
    public static volatile boolean suppressPose;
    private static Field adsProfile;
    private static Field adsWeaponId;
    private static Field adsYaw;
    private static Field adsPitch;
    private static boolean swayReflectionFailed;

    public static boolean looking() {
        return View.enabled && Look.captured && !FreeCam.active;
    }

    public static void setSuppressPose(boolean suppress) {
        suppressPose = suppress;
    }

    /** Change only the live sight alignment; setProfile would reset scope zero and mesh caches every frame. */
    public static boolean setHoldSway(String weaponId, double yaw, double pitch) {
        if (swayReflectionFailed || weaponId == null || !Double.isFinite(yaw) || !Double.isFinite(pitch)) return false;
        try {
            if (adsProfile == null) {
                Class<?> ads = Class.forName("pvads.ADS");
                adsProfile = ads.getDeclaredField("P");
                adsProfile.setAccessible(true);
                Class<?> profile = adsProfile.getType();
                adsWeaponId = profile.getDeclaredField("weaponId");
                adsYaw = profile.getDeclaredField("adjYaw");
                adsPitch = profile.getDeclaredField("adjPitch");
                adsWeaponId.setAccessible(true);
                adsYaw.setAccessible(true);
                adsPitch.setAccessible(true);
            }
            Object profile = adsProfile.get(null);
            if (profile == null || !weaponId.equals(adsWeaponId.get(profile))) return false;
            adsYaw.setFloat(profile, (float) yaw);
            adsPitch.setFloat(profile, (float) pitch);
            return true;
        } catch (ReflectiveOperationException | RuntimeException ex) {
            swayReflectionFailed = true;
            System.err.println("[ViewpointGael] ADS hold sway unavailable: " + ex);
            return false;
        }
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
