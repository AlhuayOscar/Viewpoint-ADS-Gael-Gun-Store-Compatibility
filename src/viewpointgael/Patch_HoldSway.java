/*
 * Decompiled with CFR 0.152.
 *
 * Could not load the following classes:
 *  me.zed_0xff.zombie_buddy.Patch
 *  me.zed_0xff.zombie_buddy.Patch$Argument
 *  me.zed_0xff.zombie_buddy.Patch$OnExit
 *  org.joml.Matrix4f
 *  org.joml.Vector3f
 */
package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="pvads.ADS", methodName="posed", strictMatch=true)
public final class Patch_HoldSway {
    @Patch.OnExit(suppress=Throwable.class)
    public static void exit(@Patch.Argument(value=0) Object animationPlayer) {
        HoldSway.applyToWeaponBones(animationPlayer);
    }

    private Patch_HoldSway() {
    }
}
