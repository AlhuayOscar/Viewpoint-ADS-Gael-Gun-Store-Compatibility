package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Defers PZ's body-part and armor damage calculation until the custom impact. */
@Patch(className = "zombie.CombatManager", methodName = "applyRangeHitLocationDamage", strictMatch = true)
public final class Patch_GaelBallisticRangeDamage {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.Argument(0) IsoGameCharacter target,
                                @Patch.Argument(1) HandWeapon weapon,
                                @Patch.Argument(2) int bodyPart,
                                @Patch.Argument(3) float rawDamage) {
        return PzBallisticRuntime.captureNativeDamageInputs(target, weapon, bodyPart, rawDamage);
    }

    private Patch_GaelBallisticRangeDamage() {}
}
