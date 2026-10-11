package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import viewpoint.input.ThirdPerson;

/** Keeps Viewpoint's current mode in sync when ADS forces first person temporarily. */
@Patch(className = "pvads.VP", methodName = "setThirdPerson", strictMatch = true)
public final class Patch_ADSThirdPerson {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) boolean enabled) {
        ThirdPerson.setFromADS(enabled);
    }

    private Patch_ADSThirdPerson() {}
}
