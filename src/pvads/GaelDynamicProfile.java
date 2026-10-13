package pvads;

/** Applies Gael's frame-by-frame sight offsets without rebuilding the weapon profile. */
public final class GaelDynamicProfile {
    public static boolean set(String weaponId, double x, double y, double z,
                              double pitch, double yaw, double roll, double fov) {
        if (weaponId == null || !finite(x, y, z, pitch, yaw, roll, fov)) return false;
        ADS.Profile profile = ADS.P;
        if (!profile.valid || !weaponId.equals(profile.weaponId)) return false;
        profile.adjX = (float) x;
        profile.adjY = (float) y;
        profile.adjZ = (float) z;
        profile.adjPitch = (float) pitch;
        profile.adjYaw = (float) yaw;
        profile.adjRoll = (float) roll;
        profile.fovMul = (float) Math.max(0.3, Math.min(1.2, fov));
        return true;
    }

    private static boolean finite(double... values) {
        for (double value : values) if (!Double.isFinite(value)) return false;
        return true;
    }

    private GaelDynamicProfile() {}
}
