package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoGameCharacter;

/**
 * Gael adds a pixel-offset pitch on top of the native vertical angle during OnPlayerUpdate.
 * That write runs after Viewpoint has already flattened the angle for this frame.
 */
@Patch(className = "zombie.characters.IsoGameCharacter", methodName = "setTargetVerticalAimAngle", strictMatch = true)
public class Patch_BlockVertical {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(IsoGameCharacter character, float angle) {
        return AimProbe.suppressPose && AimProbe.looking();
    }
}
