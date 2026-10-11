package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelWeaponMotion;
import zombie.characters.IsoPlayer;

@Patch(className="pvads.ADS", methodName="projectOverlay", strictMatch=true)
public final class Patch_WeaponMotion {
    @Patch.OnExit(suppress=Throwable.class)
    public static void exit(@Patch.Argument(0) IsoPlayer player, @Patch.Argument(1) float facing) {
        GaelWeaponMotion.capture(player, facing);
    }
}
