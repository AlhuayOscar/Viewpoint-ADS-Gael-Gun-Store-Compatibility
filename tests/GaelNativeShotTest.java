package pvads;

import zombie.iso.Vector3;

public final class GaelNativeShotTest {
    public static void main(String[] args) throws Exception {
        me.zed_0xff.zombie_buddy.Patch patch = viewpointgael.Patch_NativeShot.class
            .getAnnotation(me.zed_0xff.zombie_buddy.Patch.class);
        check(patch != null && patch.strictMatch(), "native hook annotation missing");
        java.lang.reflect.Method target = Class.forName(patch.className(), false,
            GaelNativeShotTest.class.getClassLoader()).getDeclaredMethod(patch.methodName(),
                Object.class, Object.class, Object.class);
        check(java.lang.reflect.Modifier.isStatic(target.getModifiers()), "ADS muzzle hook changed");
        Vector3 direction = new Vector3();
        double[][] inputs = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {0.4, -0.3, 0.8}};
        for (double[] input : inputs) {
            double[] ray = {0, 0, 0, input[0], input[1], input[2], 60};
            check(GaelNativeShot.writeDirection(direction, ray), "valid direction rejected");
            // Native ballistics scales floor-Z back to height and normalizes it.
            double x = direction.x, y = direction.y, z = direction.z * 2.4494895935058594;
            double length = Math.sqrt(x*x + y*y + z*z);
            double expectedLength = Math.sqrt(input[0]*input[0] + input[1]*input[1] + input[2]*input[2]);
            check(Math.abs(x/length - input[0]/expectedLength) < 1e-6, "X mismatch");
            check(Math.abs(y/length - input[1]/expectedLength) < 1e-6, "Y mismatch");
            check(Math.abs(z/length - input[2]/expectedLength) < 1e-6, "Z mismatch");
        }
        direction.set(1, 2, 3);
        check(!GaelNativeShot.writeDirection(direction, new double[7]), "zero direction accepted");
        check(!GaelNativeShot.writeDirection(direction, new double[]{0,0,0,Double.NaN,1,0}), "NaN accepted");
        check(!GaelNativeShot.writeDirection(direction, new double[]{0,0,0,1,Double.POSITIVE_INFINITY,0}), "infinity accepted");
        check(!GaelNativeShot.writeDirection(direction, null), "null ray accepted");
        check(!GaelNativeShot.writeDirection(direction, new double[3]), "short ray accepted");
        check(direction.x == 1 && direction.y == 2 && direction.z == 3, "invalid ray changed native aim");
        System.out.println("GaelNativeShot: installed ADS hook, direction/unit conversion and invalid-ray checks passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
