package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;

/** True Ballistics reads this ray to choose the launch path from the muzzle. */
@Patch(className = "pvads.Sight", methodName = "ray", strictMatch = true)
public final class Patch_BarrelSight {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) double[] out, @Patch.Return boolean valid) {
        boolean replaced = valid && pvads.GaelBarrelRay.replace(out);
        pvads.GaelBarrelRay.logPatchResult(out, valid, replaced);
    }

    private Patch_BarrelSight() {}
}
