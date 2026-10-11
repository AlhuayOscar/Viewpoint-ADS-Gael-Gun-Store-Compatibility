package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelNativeShot;

/** Run after ADS undoes its visual presence transform, independent of advice order. */
@Patch(className = "pvads.Presence", methodName = "afterMuzzle", strictMatch = true)
public final class Patch_NativeShot {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object controller,
                            @Patch.Argument(2) Object direction) {
        GaelNativeShot.afterPresence(controller, direction);
    }

    private Patch_NativeShot() {}
}
