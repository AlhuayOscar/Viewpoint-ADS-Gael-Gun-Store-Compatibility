package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** The five-argument Hit overload delegates here, so one patch covers both paths. */
@Patch(className = "zombie.characters.IsoGameCharacter", methodName = "Hit", strictMatch = true)
public final class Patch_LongDistanceDamage {
    @Patch.OnEnter
    public static void enter(@Patch.This IsoGameCharacter target,
                             @Patch.Argument(0) HandWeapon weapon,
                             @Patch.Argument(1) IsoGameCharacter attacker,
                             @Patch.Argument(value = 2, readOnly = false) float damage,
                             @Patch.Argument(5) boolean noSound) {
        damage = RangeBalance.damage(target, weapon, attacker, damage);
    }
}
