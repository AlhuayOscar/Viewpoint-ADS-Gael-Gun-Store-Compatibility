package pvads;

import zombie.iso.Vector3;

public final class GaelMirroredShotTest {
    public static void main(String[] args) {
        int cases = 0;
        for (double yaw : new double[]{0, 0.7, -1.2}) {
            for (double pitch : new double[]{0, 0.35, -0.4}) {
                for (double fov : new double[]{0.45, 1.0, 1.7}) {
                    for (double scale : new double[]{0, 0.5, 1, 2.25, 3, 10}) {
                        for (double[] miss : new double[][]{{0,0}, {5,0}, {-65,0}, {0,5}, {0,-65}, {90,-45}}) {
                            verify(yaw, pitch, fov, scale, miss[0], miss[1]);
                            cases++;
                        }
                    }
                }
            }
        }
        double[] ray = {4,5,6,1,0,0,60};
        check(!GaelBarrelRay.fromScreen(ray, -9999, 50, 1366,768,1,0,0), "invalid ADS sentinel accepted");
        check(!GaelBarrelRay.fromScreen(ray, 50, Double.NaN, 1366,768,1,0,0), "invalid ADS projection accepted");
        check(!GaelBarrelRay.fromScreen(ray, 50,50,1366,768,0,0,0), "invalid FOV accepted");
        check(ray[3] == 1 && ray[4] == 0 && ray[5] == 0, "invalid input mutated ray");
        verifyProgression();
        System.out.println("GaelMirroredShot: " + cases + " rendered-screen/FOV/axis/scale cases passed; native ray agrees");
    }

    private static void verify(double yaw, double pitch, double fov, double scale, double horizontal, double vertical) {
        // Start at ADS's rendered projection, not the pre-ADS model attachment.
        double centerX = 683, centerY = 384;
        double[] shot = {4,5,6,1,0,0,60};
        GaelBarrelRay.setSeparationScale(scale);
        check(GaelBarrelRay.fromScreen(shot, centerX+horizontal,centerY+vertical,1366,768,fov,yaw,pitch), "rendered axis rejected");
        GaelSightProjection.Point marker = GaelSightProjection.project(0,0,0,-shot[3],shot[5],-shot[4],yaw,pitch,fov,1366,768,60);
        check(marker != null, "projection failed");
        double focal = 768 / (2 * Math.tan(fov / 2));
        double angle = Math.toDegrees(Math.atan(Math.hypot(horizontal, vertical) / focal));
        double gain = GaelBarrelRay.angularGain(angle);
        check(Math.abs((marker.x()-centerX) - scale*gain*horizontal) < 1e-5, "yaw did not follow weapon deviation");
        check(Math.abs((marker.y()-centerY) - scale*gain*vertical) < 1e-5, "pitch did not follow weapon deviation");
        check(shot[0] == 4 && shot[1] == 5 && shot[2] == 6 && shot[6] == 60, "origin/zero changed");
        Vector3 nativeDirection = new Vector3();
        check(GaelNativeShot.writeDirection(nativeDirection, shot), "native direction rejected");
        double nx = nativeDirection.x, ny = nativeDirection.y, nz = nativeDirection.z*2.4494895935058594;
        double nl = Math.sqrt(nx*nx + ny*ny + nz*nz);
        check(Math.abs(nx/nl-shot[3]) < 1e-6 && Math.abs(ny/nl-shot[4]) < 1e-6
            && Math.abs(nz/nl-shot[5]) < 1e-6, "native and ADS ray differ");
    }

    private static void verifyProgression() {
        check(GaelBarrelRay.angularGain(0) == 1 && GaelBarrelRay.angularGain(1) == 1
                && GaelBarrelRay.angularGain(45) == 1, "deviation multiplier changed with angle");
        for (double angle = 0; angle <= 20; angle += 0.1) {
            double gain = GaelBarrelRay.angularGain(angle);
            check(gain == 1 && Double.isFinite(gain), "deviation multiplier changed with angle");
        }
        // Equal angular errors must remain 1:1 at different FOVs/resolutions.
        for (int height : new int[]{768, 1080, 1440}) {
            int width = height * 16 / 9;
            for (double fov : new double[]{0.45, 1.0, 1.7}) {
                for (double angle : new double[]{1, 5.5, 10, 20}) {
                    double focal = height / (2 * Math.tan(fov / 2));
                    double error = focal * Math.tan(Math.toRadians(angle));
                    double[] shot = {4,5,6,1,0,0,60};
                    GaelBarrelRay.setSeparationScale(2.25);
                    check(GaelBarrelRay.fromScreen(shot, width*0.5 + error, height*0.5, width,height,fov,0,0), "angular case rejected");
                    GaelSightProjection.Point point = GaelSightProjection.project(0,0,0,-shot[3],shot[5],-shot[4],0,0,fov,width,height,60);
                    check(point != null && Math.abs((point.x()-width*0.5)/error - 2.25) < 1e-6, "FOV/resolution changed measured deviation");
                }
            }
        }
        System.out.println("Progression: exact 1:1 angular deviation and 36 FOV/resolution cases passed");
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
