package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelImpactMarker;

/** Optional hooks: present only when Viewpoint True Ballistics is installed. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "impact")
public final class Patch_TBImpact {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.This Object manager, @Patch.Argument(0) Object projectile) {
        GaelImpactMarker.terminalImpact(manager, projectile);
    }
}
