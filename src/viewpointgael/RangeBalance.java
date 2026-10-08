package viewpointgael;

import zombie.SandboxOptions;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Experimental firearm range and long-distance damage sandbox balance. */
public final class RangeBalance {
    private static final float RANGE_MULTIPLIER = 1.5f;
    private static final float LONG_DAMAGE_MULTIPLIER = 0.7f;
    private static volatile boolean extendedRange = false;
    private static volatile boolean nerfLongDistances = false;
    private static volatile long nextReadNanos;

    private static void refresh() {
        long now = System.nanoTime();
        if (now < nextReadNanos) return;
        nextReadNanos = now + 1_000_000_000L;
        try {
            SandboxOptions options = SandboxOptions.instance;
            if (options == null) return;
            extendedRange = enabled(options, "ExperimentalExtendedRange", false);
            nerfLongDistances = enabled(options, "NerfLongDistances", true);
        } catch (RuntimeException ignored) {
            // Before the sandbox loads, keep the experimental change off.
        }
    }

    private static boolean enabled(SandboxOptions options, String key, boolean fallback) {
        SandboxOptions.SandboxOption option = options.getOptionByName("ViewpointGaelCompat." + key);
        if (option == null) return fallback;
        Object value = option.asConfigOption().getValueAsObject();
        return value instanceof Boolean ? (Boolean) value : fallback;
    }

    public static float range(HandWeapon weapon, float original) {
        refresh();
        if (!extendedRange || weapon == null || !weapon.isAimedFirearm() || original <= 0f) return original;
        return original * RANGE_MULTIPLIER;
    }

    public static float damage(IsoGameCharacter target, HandWeapon weapon,
                               IsoGameCharacter attacker, float original) {
        refresh();
        if (!extendedRange || !nerfLongDistances || target == null || attacker == null
                || weapon == null || !weapon.isAimedFirearm() || original <= 0f) return original;
        float normalRange = weapon.getMaxRange(attacker) / RANGE_MULTIPLIER;
        return attacker.DistToSquared(target) > normalRange * normalRange
                ? original * LONG_DAMAGE_MULTIPLIER : original;
    }

    private RangeBalance() {}
}
