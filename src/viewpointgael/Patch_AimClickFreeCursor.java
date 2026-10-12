package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;
import pvads.GaelWeaponMotion;
import zombie.characters.IsoPlayer;
import zombie.inventory.types.HandWeapon;
import zombie.ui.UIManager;

/** Project Viewpoint 0.1.6 can leave the cursor free while the FPS world is active. */
@Patch(className = "pvads.AimClick", methodName = "inWorld", strictMatch = true)
public final class Patch_AimClickFreeCursor {
    @Patch.OnEnter(skipOn = true)
    public static boolean enter() {
        if (UIManager.isMouseOverInventory() || UIManager.isModalVisible()) return false;
        IsoPlayer player = IsoPlayer.players[0];
        return player != null && player.isAiming()
                && player.getPrimaryHandItem() instanceof HandWeapon weapon
                && weapon.isAimedFirearm() && GaelWeaponMotion.ready();
    }

    private Patch_AimClickFreeCursor() {}
}
