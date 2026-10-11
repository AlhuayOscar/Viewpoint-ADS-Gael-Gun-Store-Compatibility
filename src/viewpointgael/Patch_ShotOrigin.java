package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Apply the local model-space origin adjustment after both Presence and LeanShot finish. */
@Patch(className = "pvads.LeanShot", methodName = "afterMuzzle", strictMatch = true)
public final class Patch_ShotOrigin {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object controller, @Patch.Argument(1) Object muzzle) {
        GaelNativeShot.afterLean(controller, muzzle);
    }

    private Patch_ShotOrigin() {}
}
