package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.inventory.types.HandWeapon;

/** Return an expanded effective range without mutating Gael's dynamic-ammo stats. */
public final class Patch_ExtendedRange {
    @Patch(className = "zombie.inventory.types.HandWeapon", methodName = "getMaxRange", strictMatch = true)
    public static class Base {
        @Patch.OnExit
        public static void exit(@Patch.This HandWeapon weapon, @Patch.Return(readOnly = false) float range) {
            range = RangeBalance.range(weapon, range);
        }
    }

    @Patch(className = "zombie.inventory.types.HandWeapon", methodName = "getMaxRange")
    public static class WithCharacter {
        @Patch.OnExit
        public static void exit(@Patch.This HandWeapon weapon,
                                @Patch.Argument(0) zombie.characters.IsoGameCharacter character,
                                @Patch.Return(readOnly = false) float range) {
            range = RangeBalance.range(weapon, range);
        }
    }

    private Patch_ExtendedRange() {}
}
