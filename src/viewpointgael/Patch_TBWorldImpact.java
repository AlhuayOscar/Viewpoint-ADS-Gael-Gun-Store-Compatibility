package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelImpactMarker;

/** Captures barrel-blocked shots and world collisions, including walls, trees and furniture. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "worldImpact")
public final class Patch_TBWorldImpact {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object projectile, @Patch.Argument(1) Object point,
                            @Patch.Argument(2) int worldKind) {
        GaelImpactMarker.worldImpact(projectile, point, worldKind);
    }
}
