package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Delays PZ's target reaction and critical roll until the custom projectile hits. */
@Patch(className = "zombie.CombatManager", methodName = "processHit", strictMatch = true)
public final class Patch_GaelBallisticHitReaction {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.Argument(0) HandWeapon weapon,
                                @Patch.Argument(1) IsoGameCharacter attacker,
                                @Patch.Argument(2) IsoGameCharacter target) {
        return PzBallisticRuntime.suppressNativeFiringReaction(target, attacker, weapon);
    }

    private Patch_GaelBallisticHitReaction() {}
}
