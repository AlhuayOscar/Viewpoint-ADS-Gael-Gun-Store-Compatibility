import java.nio.file.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
public class GaelLuaRecoilTest {
 public static void main(String[] args) throws Exception {
  J2SEPlatform platform = J2SEPlatform.getInstance();
  KahluaTable env = platform.newEnvironment();
  KahluaThread thread = new KahluaThread(platform, env); thread.debugOwnerThread = Thread.currentThread();
  String stub = "require=function() end; Events={OnGameBoot={Add=function() end},OnGameStart={Add=function() end}};";
  String source = stub + Files.readString(Path.of(args[0])) + Files.readString(Path.of(args[1])) + Files.readString(Path.of(args[2]));
  String checks = """
   local balance=PVADS_GaelRecoilBalance
   local original={weaponId='Base.Automag357',gunKick=10,gunBack=0.04,adjYaw=2,adjPitch=3}
   local received
   PVADS_setProfile=function(p) received=p end
   balance.install()
   for i=1,100 do
    balance.install()
    PVADS_setProfile(original)
    assert(math.abs(received.gunKick-7)<0.000001)
    assert(math.abs(received.gunBack-0.012)<0.000001)
   end
   assert(original.gunKick==10 and original.gunBack==0.04)
   assert(received.adjYaw==2 and received.adjPitch==3)
   PVADS_setProfile(received)
   assert(math.abs(received.gunBack-0.012)<0.000001)
   local other={weaponId='Other.Unknown',gunKick=10,gunBack=0.04}
   PVADS_setProfile(other)
   assert(received==other)
   for _,shot in ipairs({1,3,4,5,6,20,21,26,27}) do
    local stage=shot<=3 and 0.5 or (shot<=5 and 0.75 or 1)
    local yaw,pitch=balance.angular(4*stage,-8*stage,4*stage,-8*stage)
    assert(math.abs(yaw-2.8*stage)<0.000001)
    assert(math.abs(pitch+5.6*stage)<0.000001)
   end
   local expectedYaw,expectedPitch=PVADS_GaelAlignment.response(0.3,-0.2)
   local yaw,pitch=balance.angular(2.3,-4.2,2,-4)
   assert(math.abs(yaw-expectedYaw-1.4)<0.000001)
   assert(math.abs(pitch-expectedPitch+2.8)<0.000001)
   -- First 3/5 and single-shot behaviour is preserved exactly.
   for _,shot in ipairs({1,3,4,5}) do
    assert(balance.burstPeak(-0.7,2,shot,true,false,12)==-0.7)
   end
   assert(balance.burstPeak(-0.7,2,6,false,false,12)==-0.7)
   assert(balance.burstPeak(-0.7,2,21,true,true,12)==-0.7)
   local peak=0.5
   for shot=6,20 do
    local nextPeak=balance.burstPeak(shot%2==0 and -0.5 or 0.5,peak,shot,true,false,12)
    assert(nextPeak>peak and math.abs(nextPeak-peak-0.4)<0.000001)
    peak=nextPeak
   end
   assert(math.abs(peak-6.5)<0.000001)
   assert(balance.burstPeak(20,11,6,true,false,12)==12)
   assert(balance.burstPeak(1,-2,6,true,false,8)<-2)
   assert(balance.armPenalty(0,0)==0 and balance.armPenalty(20,0)==3)
   assert(balance.armPenalty(0,100)==3 and balance.armPenalty(0,50)==1.5)
   assert(balance.movementFactor(0,0)==1 and balance.movementFactor(4,3)==3.5)
   assert(math.abs(balance.longBurstAnchor(3,-6.5,0.4)*0.4-6.5)<0.000001)
   """;
  LuaClosure closure = LuaCompiler.loadstring(source+checks,"recoil-balance-test",env);
  Object[] result=thread.pcall(closure,new Object[0]);
  if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(java.util.Arrays.toString(result));
  String motion = Files.readString(Path.of(args[3]));
  String publish = motion.substring(motion.indexOf("local function publishRecoilAim("), motion.indexOf("local function resetIronFocusState("));
  String push = motion.substring(motion.indexOf("local function pushDynamicProfile("), motion.indexOf("local function updateIronFocus("));
  String motionChecks = """
   PVADS={}; SandboxVars={ViewpointGaelCompat={}}
   recoilYaw,recoilPitch,releaseRegripYaw,releaseRegripPitch=0,0,0,0
   isCalibratingBlocked=function() return false end
   renderedShotRayActive=function() return true end
   getCore=function() return {getScreenHeight=function() return 1080 end} end
   local applied,command,profileOut
   ViewpointGael={Aim={
    setWeaponMotion=function(weapon,yaw,pitch,roll) command={weapon,yaw,pitch,roll} end,
    setDynamicProfile=function(weapon,x,y,z,pitch,yaw,roll,fov) applied={x,y,z,pitch,yaw,roll} end,
    setRecoilAim=function() end
   }}
   PVADS_setProfile=function(p) profileOut=p end
   """ + publish + push + """
   local base={weaponId='Base.MP5K',adjX=0.01,adjY=-0.018,adjZ=-0.12,adjYaw=2,adjPitch=-0.8,adjRoll=180}
   local dynamic={weaponId=base.weaponId,adjX=0.02,adjY=0.022,adjZ=-0.10,adjYaw=3,adjPitch=1.2,adjRoll=183}
   pushDynamicProfile(dynamic,base)
   publishRecoilAim(base,dynamic,true)
   assert(profileOut.adjYaw==2 and profileOut.adjPitch==-0.8 and profileOut.adjRoll==180)
   assert(math.abs(profileOut.adjY-(-0.006))<0.000001)
   assert(dynamic.adjYaw==3 and dynamic.adjRoll==183)
   assert(command[1]==base.weaponId and command[2]>0 and command[3]>0 and command[4]==3)
   publishRecoilAim(base,nil,false)
   assert(command[2]==0 and command[3]==0 and command[4]==0)
   """;
  result=thread.pcall(LuaCompiler.loadstring(motionChecks,"motion-routing-test",env),new Object[0]);
  if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(java.util.Arrays.toString(result));
  // Compile the whole production file as well; the routing test executes its actual functions.
  LuaCompiler.loadstring(motion,"iron-focus-syntax",env);
  System.out.println("Recoil Lua: 70/30 profile weights, 100 repeated updates, saved values, foreign weapons, burst thresholds and separate hold/recoil passed");
  System.out.println("Motion Lua: yaw/pitch/roll routed after ADS alignment, 30% posture translation and all-axis reset passed");
  System.out.println("Burst Lua: shots 1-5 preserved; shots 6-20 accumulate bounded angular error; long burst preserved; local arm pain and exertion affect walking rotation");
 }
}
