package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import viewpoint.input.ThirdPerson;

/** Mirrors Viewpoint's renamed third-person state into the legacy ADS alias. */
@Patch(className = "viewpoint.camera.ThirdPerson", methodName = "poll", strictMatch = true)
public final class Patch_ViewpointThirdPerson {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit() {
        ThirdPerson.syncFromViewpoint();
    }

    private Patch_ViewpointThirdPerson() {}
}
