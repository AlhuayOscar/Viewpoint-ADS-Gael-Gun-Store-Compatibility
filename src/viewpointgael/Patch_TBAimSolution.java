package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Set the ADS weapon's physical shot direction before True Ballistics spawns or records the round. */
@Patch(className = "vtb.aiming.AimProvider", methodName = "solve", strictMatch = true)
public final class Patch_TBAimSolution {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object shooter, @Patch.Argument(1) Object weapon,
                            @Patch.Argument(8) Object solution, @Patch.Return boolean success) {
        if (success) GaelNativeShot.correctTrueBallisticsSolution(shooter, weapon, solution);
    }

    private Patch_TBAimSolution() {}
}
