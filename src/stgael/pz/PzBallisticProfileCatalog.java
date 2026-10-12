package stgael.pz;

import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

import stgael.ballistics.BallisticProfile;
import zombie.inventory.types.HandWeapon;
import zombie.scripting.objects.AmmoType;
import zombie.scripting.objects.Item;

/** Explicit per-calibre profile registry; PZ does not define projectile velocity. */
public final class PzBallisticProfileCatalog {
    private static final ConcurrentMap<String, BallisticProfile> PROFILES = new ConcurrentHashMap<>();
    private static final double STANDARD_GRAVITY = 9.81;
    private static final double DEFAULT_DRAG_PER_SECOND = 0.18;
    private static final double DEFAULT_MAX_DISTANCE_METRES = 120.0;
    private static final double DEFAULT_MAX_FLIGHT_SECONDS = 0.5;

    static {
        // Nominal commercial-load muzzle velocities, converted from manufacturer
        // catalog FPS. These are starting profiles, not per-load chronograph data.
        registerDefault(AmmoType.BULLETS_9MM, 332.0);
        registerDefault(AmmoType.BULLETS_38, 271.0);
        registerDefault(AmmoType.BULLETS_357, 378.0);
        registerDefault(AmmoType.BULLETS_44, 369.0);
        registerDefault(AmmoType.BULLETS_45, 274.0);
        registerDefault(AmmoType.BULLETS_556, 965.0);
        registerDefault(AmmoType.BULLETS_308, 860.0);
    }

    private PzBallisticProfileCatalog() {}

    private static void registerDefault(AmmoType ammoType, double velocity) {
        register(ammoType.getItemKey(), new BallisticProfile(velocity, STANDARD_GRAVITY,
                DEFAULT_DRAG_PER_SECOND, DEFAULT_MAX_DISTANCE_METRES, DEFAULT_MAX_FLIGHT_SECONDS));
    }

    /** Register an independently tuned profile under PZ's AmmoType item key. */
    public static void register(String ammoTypeKey, BallisticProfile profile) {
        String key = normalize(ammoTypeKey);
        if (key.isEmpty()) throw new IllegalArgumentException("Ammo type key must not be blank");
        if (profile == null) throw new NullPointerException("profile");
        PROFILES.put(key, profile);
    }

    public static BallisticProfile forWeapon(HandWeapon weapon) {
        if (weapon == null) return null;
        Item scriptItem = weapon.getScriptItem();
        if (scriptItem == null) return null;
        AmmoType ammoType = scriptItem.getAmmoType();
        if (ammoType == null) return null;
        return PROFILES.get(normalize(ammoType.getItemKey()));
    }

    public static String ammoTypeKey(HandWeapon weapon) {
        if (weapon == null || weapon.getScriptItem() == null) return null;
        AmmoType ammoType = weapon.getScriptItem().getAmmoType();
        return ammoType == null ? null : ammoType.getItemKey();
    }

    public static void clear() { PROFILES.clear(); }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
