package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;

/** Applies recoil after True Ballistics has resolved ADS, barrel and zeroing. */
@Patch(className = "vtb.aiming.AimProvider", methodName = "solve", strictMatch = true)
public final class Patch_TrueBallisticsShotDirection {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) IsoPlayer player,
                            @Patch.Argument(8) Object solution,
                            @Patch.Return boolean valid) {
        pvads.GaelRecoilAim.onShotSolution(player, solution, valid);
    }

    private Patch_TrueBallisticsShotDirection() {}
}
