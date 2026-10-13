package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoGameCharacter;

/** Add the procedural recoil to Viewpoint's shot direction after its native recoil. */
public final class Patch_RecoilAim {
    @Patch(className = "viewpoint.input.CrosshairAim", methodName = "yaw", strictMatch = true)
    public static final class Yaw {
        @Patch.OnExit(suppress = Throwable.class)
        public static void exit(@Patch.Argument(0) IsoGameCharacter character,
                                @Patch.Return(readOnly = false) float angle) {
            angle = pvads.GaelRecoilAim.yaw(character, angle);
        }
    }

    @Patch(className = "viewpoint.input.CrosshairAim", methodName = "pitch", strictMatch = true)
    public static final class Pitch {
        @Patch.OnExit(suppress = Throwable.class)
        public static void exit(@Patch.Argument(0) IsoGameCharacter character,
                                @Patch.Return(readOnly = false) float angle) {
            angle = pvads.GaelRecoilAim.pitch(character, angle);
        }
    }

    private Patch_RecoilAim() {}
}
