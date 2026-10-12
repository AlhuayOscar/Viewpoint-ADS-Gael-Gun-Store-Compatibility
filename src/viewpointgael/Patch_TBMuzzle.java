package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Apply the persisted per-weapon muzzle offset before True Ballistics checks the barrel path. */
@Patch(className = "vtb.aiming.MuzzleResolver", methodName = "resolve", strictMatch = true)
public final class Patch_TBMuzzle {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object character, @Patch.Argument(2) Object muzzle) {
        GaelNativeShot.applyTrueBallisticsMuzzleCalibration(character, muzzle);
    }

    private Patch_TBMuzzle() {}
}
