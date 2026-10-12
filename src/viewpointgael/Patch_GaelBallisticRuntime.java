package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;

/** Advances independent projectiles after each game-time update on the PZ thread. */
@Patch(className = "zombie.GameTime", methodName = "update", strictMatch = true)
public final class Patch_GaelBallisticRuntime {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) boolean sleeping) {
        PzBallisticRuntime.updateFromGame();
    }

    private Patch_GaelBallisticRuntime() {}
}
