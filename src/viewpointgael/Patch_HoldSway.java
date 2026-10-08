package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import org.joml.Matrix4f;
import org.joml.Vector3f;

/** Extend PVADS' solved pose before it drives the arm bones, sight overlay, and sight ray. */
@Patch(className = "pvads.ADS", methodName = "solve")
public final class Patch_HoldSway {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(3) Vector3f eye,
                            @Patch.Argument(4) Vector3f direction,
                            @Patch.Argument(6) float progress,
                            @Patch.Argument(7) Matrix4f pose) {
        HoldSway.apply(eye, direction, progress, pose);
    }

    private Patch_HoldSway() {}
}
