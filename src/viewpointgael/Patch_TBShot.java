package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelImpactMarker;

/** Clears the previous endpoint when a new real shot begins. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "spawnShot")
public final class Patch_TBShot {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object shooter, @Patch.Argument(2) boolean test,
                            @Patch.Return Object group) {
        GaelImpactMarker.shotStarted(shooter, group, test);
    }
}
