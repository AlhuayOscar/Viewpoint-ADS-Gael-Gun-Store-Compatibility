package pvads;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.joml.Quaternionf;

public class GaelPhysicalAxisTest {
    public static void main(String[] args) throws Exception {
        int count = 0;
        for (float calibrationRoll : new float[]{0,90,180}) {
            for (float yaw : new float[]{-8,0,8}) {
                for (float pitch : new float[]{-6,0,6}) {
                    for (float translation : new float[]{0,0.02f,0.3f}) {
                        Vector3f raw = new Vector3f(0,1,0);
                        Quaternionf calibration = new Quaternionf().rotateZ((float)Math.toRadians(2))
                                .rotateX((float)Math.toRadians(-0.8)).rotateY((float)Math.toRadians(calibrationRoll));
                        Vector3f reference = calibration.transform(new Vector3f(raw));
                        Matrix4f weapon = new Matrix4f().rotateX(-1.2f).rotateY(0.7f);
                        Matrix4f pose = new Matrix4f().translate(translation,-translation,2*translation)
                                .rotateY((float)Math.toRadians(yaw)).rotateX((float)Math.toRadians(pitch));
                        Vector3f expected = weapon.transformDirection(new Vector3f(raw));
                        pose.transformDirection(expected).normalize();
                        Vector3f actual = new Vector3f();
                        GaelWeaponMotion.physicalDirection(reference,2,-0.8f,calibrationRoll,weapon,pose,actual,new Quaternionf());
                        if (actual.distance(expected) > 1e-5) throw new AssertionError("Reference calibration/offset corrupted physical direction");
                        var barrel = GaelSightProjection.project(0,0,0,actual.x,actual.y,actual.z,Math.PI/2,0,1,1366,768,60);
                        if (barrel == null) throw new AssertionError("Physical barrel projection rejected");
                        double[] ray = {0,0,0,1,0,0,60};
                        GaelBarrelRay.setSeparationScale(1);
                        if (!GaelBarrelRay.fromScreen(ray,barrel.x(),barrel.y(),1366,768,1,Math.PI/2,0)) throw new AssertionError("Physical axis could not drive mirrored ray");
                        var marker = GaelSightProjection.project(0,0,0,-ray[3],ray[5],-ray[4],Math.PI/2,0,1,1366,768,60);
                        if (marker == null || (marker.x()-683)*(barrel.x()-683) < -1e-5
                                || (marker.y()-384)*(barrel.y()-384) < -1e-5) throw new AssertionError("Shot marker did not follow physical barrel deviation");
                        count++;
                    }
                }
            }
        }
        Vector3f actual = new Vector3f();
        GaelWeaponMotion.physicalDirection(new Vector3f(0,1,0),0,0,0,new Matrix4f(),
                new Matrix4f().translate(3,4,5).rotateY(1.7f),actual,new Quaternionf());
        if (actual.distance(new Vector3f(0,1,0)) > 1e-6) throw new AssertionError("Pure roll or translation changed barrel direction");
        Class<?> ads = Class.forName("pvads.ADS",false,GaelPhysicalAxisTest.class.getClassLoader());
        ads.getDeclaredMethod("projectOverlay",zombie.characters.IsoPlayer.class,float.class,int.class,float.class);
        for (String name : new String[]{"W","M","dw"}) ads.getDeclaredField(name).setAccessible(true);
        Class.forName("pvads.Presence",false,GaelPhysicalAxisTest.class.getClassLoader()).getDeclaredField("shotFix").setAccessible(true);
        System.out.println("Physical axis: " + count + " calibrated roll/yaw/pitch/offset cases, pure roll/translation and installed ADS hook passed");
    }
}
