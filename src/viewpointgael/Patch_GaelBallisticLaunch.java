package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import stgael.pz.PzBallisticRuntime;
import zombie.characters.IsoGameCharacter;
import zombie.inventory.types.HandWeapon;

/** Launches SGTB after PZ processed the accepted shot and updated its muzzle solution. */
@Patch(className = "zombie.CombatManager", methodName = "fireWeapon", strictMatch = true)
public final class Patch_GaelBallisticLaunch {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) HandWeapon weapon,
                             @Patch.Argument(1) IsoGameCharacter shooter) {
        PzBallisticRuntime.launchStagedNativeShot(shooter, weapon);
    }

    private Patch_GaelBallisticLaunch() {}
}
