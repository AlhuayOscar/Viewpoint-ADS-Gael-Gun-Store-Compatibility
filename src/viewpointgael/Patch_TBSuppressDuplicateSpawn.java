package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;

/** Lets the independent SGTB simulation own a shot it already launched successfully. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "spawnShot")
public final class Patch_TBSuppressDuplicateSpawn {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(@Patch.Argument(0) Object shooter,
                                @Patch.Argument(1) Object weapon,
                                @Patch.Argument(2) boolean test) {
        return PzBallisticRuntime.shouldSuppressTrueBallisticsSpawn(shooter, weapon, test);
    }

    private Patch_TBSuppressDuplicateSpawn() {}
}
