package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Opens a narrowly scoped projectile-ownership window around PZ's firing pass. */
@Patch(className = "zombie.CombatManager", methodName = "attackCollisionCheck", strictMatch = true)
public final class Patch_GaelBallisticFiring {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) IsoGameCharacter shooter,
                             @Patch.Argument(1) HandWeapon weapon) {
        PzBallisticRuntime.beginNativeShot(shooter, weapon);
    }

    @Patch.OnExit(suppress = Throwable.class)
    public static void exit() {
        PzBallisticRuntime.endNativeShot();
    }

    private Patch_GaelBallisticFiring() {}
}
