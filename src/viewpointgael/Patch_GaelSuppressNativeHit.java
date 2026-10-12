package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Prevents PZ's instant character damage only when SGTB owns the fired projectile. */
@Patch(className = "zombie.characters.IsoGameCharacter", methodName = "Hit")
public final class Patch_GaelSuppressNativeHit {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This IsoGameCharacter target,
                                @Patch.Argument(0) HandWeapon weapon,
                                @Patch.Argument(1) IsoGameCharacter attacker,
                                @Patch.Argument(2) float damage,
                                @Patch.Argument(4) float rangeMultiplier) {
        return PzBallisticRuntime.captureAndSuppressNativeHit(
                target, weapon, attacker, damage, rangeMultiplier);
    }

    private Patch_GaelSuppressNativeHit() {}
}
