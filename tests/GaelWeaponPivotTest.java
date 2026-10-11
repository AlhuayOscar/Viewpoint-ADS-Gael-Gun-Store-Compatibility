package viewpointgael;

import org.joml.Matrix4f;
import org.joml.Vector3f;

import me.zed_0xff.zombie_buddy.Patch;

public class GaelWeaponPivotTest {
    public static void main(String[] args) throws Exception {
        var hook = Patch_HoldSway.class.getDeclaredMethod("exit",Vector3f.class,Vector3f.class,float.class,Matrix4f.class);
        int argument = hook.getParameterAnnotations()[0][0] instanceof Patch.Argument value ? value.value() : -1;
        if (argument != 0) throw new AssertionError("Rotation still uses eye instead of weapon sight");
        for (float yaw : new float[]{-8,0,8}) {
            for (float pitch : new float[]{-6,0,6}) {
                Vector3f sight = new Vector3f(1,2,3), forward = new Vector3f(0,0,-1);
                Matrix4f base = new Matrix4f().translate(0.1f,0.2f,0.3f);
                Vector3f pivot = base.transformPosition(new Vector3f(sight)).fma(-0.15f,forward);
                Vector3f localPivot = new Matrix4f(base).invert().transformPosition(new Vector3f(pivot));
                Matrix4f rotated = new Matrix4f(base);
                HoldSway.rotatePose(sight,forward,yaw,pitch,1,rotated);
                Vector3f after = rotated.transformPosition(localPivot,new Vector3f());
                if (after.distance(pivot) > 1e-5) throw new AssertionError("Weapon rear pivot translated during rotation");
                Vector3f actual = rotated.transformDirection(new Vector3f(forward)).normalize();
                Vector3f expected = new Matrix4f().rotateY((float)Math.toRadians(yaw))
                        .rotate((float)Math.toRadians(pitch),1,0,0).transformDirection(new Vector3f(forward)).normalize();
                if (actual.distance(expected) > 1e-5) throw new AssertionError("Yaw/pitch failed to rotate barrel direction");
                Vector3f sightAfter = rotated.transformPosition(new Vector3f(sight));
                if ((yaw != 0 || pitch != 0) && sightAfter.distance(base.transformPosition(new Vector3f(sight))) < 0.001) throw new AssertionError("Angular motion did not move the front sight about the rear pivot");
            }
        }
        Vector3f pivot = new Vector3f(0.2f,0.3f,0.4f), forward = new Vector3f(0,0,-1);
        Matrix4f rolled = new Matrix4f();
        HoldSway.rotateAroundPivot(pivot,forward,0,0,3,1,rolled);
        if (rolled.transformPosition(new Vector3f(pivot)).distance(pivot)>1e-5) throw new AssertionError("Roll moved grip");
        if (rolled.transformDirection(new Vector3f(forward)).distance(forward)>1e-5) throw new AssertionError("Pure barrel roll changed bore direction");
        if (rolled.transformDirection(new Vector3f(0,1,0)).distance(new Vector3f(0,1,0))<0.01) throw new AssertionError("Roll failed to tilt weapon");
        System.out.println("Weapon pivot: 9 yaw/pitch cases plus physical roll rotate weapon while keeping grip fixed; pure roll preserves bore direction");
    }
}
