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
    private static volatile boolean headshotDamageBonus = true;
    private static volatile long nextReadNanos;
    private static IsoGameCharacter pendingHeadTarget;
    private static IsoGameCharacter pendingHeadAttacker;
    private static HandWeapon pendingHeadWeapon;

    public static boolean markHeadshot(IsoGameCharacter target, IsoGameCharacter attacker,
                                       HandWeapon weapon, boolean headHit) {
        refresh();
        pendingHeadTarget = null;
        pendingHeadAttacker = null;
        pendingHeadWeapon = null;
        if (!headshotDamageBonus || !headHit || target == null || attacker == null || weapon == null
                || !attacker.isAiming() || !weapon.isAimedFirearm()) return false;
        float distanceSquared = attacker.DistToSquared(target);
        if (distanceSquared < 1f || distanceSquared > 64f) return false;
        pendingHeadTarget = target;
        pendingHeadAttacker = attacker;
        pendingHeadWeapon = weapon;
        return true;
    }

    private static boolean consumeHeadshot(IsoGameCharacter target,
                                           IsoGameCharacter attacker,
                                           HandWeapon weapon) {
        boolean match = target == pendingHeadTarget && attacker == pendingHeadAttacker
                && weapon == pendingHeadWeapon;
        pendingHeadTarget = null;
        pendingHeadAttacker = null;
        pendingHeadWeapon = null;
        return match;
    }

    private static void refresh() {
        long now = System.nanoTime();
        if (now < nextReadNanos) return;
        nextReadNanos = now + 1_000_000_000L;
        try {
            SandboxOptions options = SandboxOptions.instance;
            if (options == null) return;
            extendedRange = enabled(options, "ExperimentalExtendedRange", true);
            nerfLongDistances = enabled(options, "NerfLongDistances", true);
            headshotDamageBonus = enabled(options, "HeadshotDamageBonus", true);
        } catch (RuntimeException ignored) {
            // Before the sandbox loads, keep the last known values.
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
        if (target == null || attacker == null || weapon == null || original <= 0f) {
            consumeHeadshot(target, attacker, weapon);
            return original;
        }
        boolean headshot = consumeHeadshot(target, attacker, weapon);
        float damage = original;
        if (extendedRange && nerfLongDistances && weapon.isAimedFirearm()) {
            float normalRange = weapon.getMaxRange(attacker) / RANGE_MULTIPLIER;
            if (attacker.DistToSquared(target) > normalRange * normalRange) {
                damage *= LONG_DAMAGE_MULTIPLIER;
            }
        }
        return headshot ? damage * 1.30f : damage;
    }

    private RangeBalance() {}
}
