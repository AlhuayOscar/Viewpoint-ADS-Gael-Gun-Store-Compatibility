package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;

/** Defers the provisional camera target's helmet effect until projectile impact. */
@Patch(className = "zombie.characters.IsoGameCharacter", methodName = "helmetFall", strictMatch = true)
public final class Patch_GaelBallisticHelmetFall {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.This IsoGameCharacter target) {
        return PzBallisticRuntime.suppressNativeHelmetFall(target);
    }

    private Patch_GaelBallisticHelmetFall() {}
}
