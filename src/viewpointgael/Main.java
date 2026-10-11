package viewpointgael;

import java.lang.reflect.Method;

import viewpoint.input.ThirdPerson;

/** Re-runs the ADS Viewpoint bridge after this jar has entered the shared classpath. */
public final class Main {
    private Main() {}

    public static void main(String[] args) {
        try {
            ThirdPerson.syncFromViewpoint();
            Class<?> bridge = Class.forName("pvads.VP");
            Method init = bridge.getDeclaredMethod("init");
            init.setAccessible(true);
            init.invoke(null);
            System.out.println("[ViewpointGael] Project Viewpoint ADS bridge reinitialized against the current Viewpoint API.");
        } catch (Throwable failure) {
            System.err.println("[ViewpointGael] Could not reinitialize the Project Viewpoint ADS bridge: " + failure);
        }
    }
}
