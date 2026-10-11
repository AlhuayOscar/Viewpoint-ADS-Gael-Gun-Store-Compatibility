package viewpoint.input;

import viewpoint.core.View;

/** Compatibility alias for Project Viewpoint ADS versions that read the old field. */
public final class ThirdPerson {
    public static volatile boolean active;

    private ThirdPerson() {}

    public static void syncFromViewpoint() {
        active = View.thirdPerson;
    }

    public static void setFromADS(boolean enabled) {
        View.thirdPerson = enabled;
        active = enabled;
    }
}
