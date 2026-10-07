package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoGameCharacter;

/**
 * While the Lua guard is up, ignore Gael's isometric screenToIso facing write.
 * Viewpoint's own setForwardDirection(Vector2) from setAngleFromAim is a different overload.
 */
@Patch(className = "zombie.characters.IsoGameCharacter", methodName = "setForwardDirection", strictMatch = true)
public class Patch_BlockForward {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter(IsoGameCharacter character, float directionX, float directionY) {
        return AimProbe.suppressPose && AimProbe.looking();
    }
}
