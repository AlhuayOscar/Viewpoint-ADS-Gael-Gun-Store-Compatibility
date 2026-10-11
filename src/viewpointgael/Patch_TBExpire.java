package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelImpactMarker;

/** Keeps the actual terminal point when a round runs out of range or lifetime without a collision. */
@Patch(className = "vtb.projectile.BallisticsManager", methodName = "expire")
public final class Patch_TBExpire {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object projectile) {
        GaelImpactMarker.expired(projectile);
    }
}
