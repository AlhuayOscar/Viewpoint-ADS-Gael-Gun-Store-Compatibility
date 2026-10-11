package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelImpactMarker;

/** Captures Viewpoint's exact camera snapshot so impact coordinates can be placed in the HUD. */
@Patch(className = "viewpoint.input.CrosshairAim", methodName = "snapshot")
public final class Patch_ImpactCamera {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) Object frame) {
        GaelImpactMarker.captureCamera(frame);
    }
}
