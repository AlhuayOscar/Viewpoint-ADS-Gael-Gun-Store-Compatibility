package viewpointgael;

import me.zed_0xff.zombie_buddy.Patch;

/** Lets ADS continue when a weapon attachment has a model script with no name. */
@Patch(className = "pvads.ADS", methodName = "slidePart", strictMatch = true)
public final class Patch_ADSSlideNullModel {
    private static final String NULL_MODEL_NAME_ERROR = "ModelScript.getName()";

    @Patch.OnExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@Patch.Thrown(readOnly = false) Throwable thrown) {
        if (thrown instanceof NullPointerException
                && thrown.getMessage() != null
                && thrown.getMessage().contains(NULL_MODEL_NAME_ERROR)) {
            System.out.println("[ViewpointGael] ADS ignored a weapon part with a null model name.");
            thrown = null;
        }
    }

    private Patch_ADSSlideNullModel() {}
}
