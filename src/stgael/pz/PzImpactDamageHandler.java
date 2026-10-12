package stgael.pz;

import java.util.Objects;
import java.lang.reflect.Method;

import stgael.ballistics.BallisticCollision;
import stgael.ballistics.BallisticEngine;
import zombie.CombatManager;
import zombie.characters.IsoGameCharacter;
import zombie.core.physics.BallisticsController;
import zombie.inventory.types.HandWeapon;
import zombie.network.GameClient;
import zombie.core.physics.RagdollBodyPart;
import zombie.iso.Vector2;
import zombie.vehicles.BaseVehicle;

/** Applies a confirmed character impact through PZ's native character hit pipeline. */
public final class PzImpactDamageHandler {
    private static final Method RANGE_HIT_DAMAGE = rangeHitDamageMethod();
    public Result apply(BallisticEngine.Impact impact, IsoGameCharacter shooter,
                        HandWeapon weapon, DamagePlan plan) {
        Objects.requireNonNull(impact, "impact");
        Objects.requireNonNull(plan, "plan");
        BallisticCollision collision = impact.collision();
        if (shooter == null || weapon == null) {
            return new Result(Status.INVALID_TARGET, collision.target(), 0.0f, -1, -1);
        }
        if (GameClient.client) {
            return new Result(Status.CLIENT_NEEDS_SERVER_VALIDATION, collision.target(), 0.0f, -1, -1);
        }
        if (collision.kind() == BallisticCollision.Kind.VEHICLE
                && collision.target() instanceof BaseVehicle vehicle) {
            float damage = plan.baseDamage() * plan.rangeMultiplier();
            if (!Float.isFinite(damage) || damage <= 0.0f) {
                return new Result(Status.INVALID_TARGET, vehicle, 0.0f, -1, -1);
            }
            boolean applied = vehicle.processHit(shooter, weapon, damage);
            if (applied) CombatManager.getInstance().processMaintenanceCheck(shooter, weapon, vehicle);
            return new Result(applied ? Status.APPLIED : Status.INVALID_TARGET, vehicle,
                    applied ? damage : 0.0f, -1, -1);
        }
        if (collision.kind() != BallisticCollision.Kind.CHARACTER
                || !(collision.target() instanceof IsoGameCharacter target)) {
            return new Result(Status.NOT_A_CHARACTER_HIT, collision.target(), 0.0f, -1, -1);
        }
        if (target == shooter || target.isDead()) {
            return new Result(Status.INVALID_TARGET, target, 0.0f, -1, -1);
        }

        int impactBodyPart = bodyPartAtImpact(target, collision.position());
        // processHit normally reads a pre-shot camera-target cache. Temporarily
        // replace that entry with this projectile's actual contact so PZ chooses
        // the impact body part and matching hit reaction from the ballistic hit.
        // Restore the cache immediately; it is shared with the next native shot.
        shooter.setCriticalHit(plan.critical());
        int reactionBodyPart = processImpactReaction(shooter, weapon, target,
                collision.position(), impactBodyPart);
        float bodyPartDamage = applyRangeHitLocationDamage(target, weapon, impactBodyPart,
                plan.baseDamage());
        target.helmetFall(impactBodyPart == RagdollBodyPart.BODYPART_HEAD.ordinal());
        float damage = target.Hit(weapon, shooter, bodyPartDamage, false, plan.rangeMultiplier());
        return new Result(Status.APPLIED, target, damage, impactBodyPart, reactionBodyPart);
    }

    private static int bodyPartAtImpact(IsoGameCharacter target,
                                        stgael.ballistics.BallisticVector3 position) {
        double height = position.z() - target.getZ() * 2.4494895935058594;
        if (height >= 1.43) return RagdollBodyPart.BODYPART_HEAD.ordinal();
        if (height >= 0.78) return RagdollBodyPart.BODYPART_SPINE.ordinal();
        if (height >= 0.58) return RagdollBodyPart.BODYPART_PELVIS.ordinal();

        Vector2 facing = target.getForwardDirection();
        double dx = position.x() - target.getX();
        double dy = position.y() - target.getY();
        double side = facing == null ? 0.0 : facing.x * dy - facing.y * dx;
        boolean left = side > 0.0;
        if (height >= 0.30) {
            return (left ? RagdollBodyPart.BODYPART_LEFT_UPPER_LEG
                    : RagdollBodyPart.BODYPART_RIGHT_UPPER_LEG).ordinal();
        }
        return (left ? RagdollBodyPart.BODYPART_LEFT_LOWER_LEG
                : RagdollBodyPart.BODYPART_RIGHT_LOWER_LEG).ordinal();
    }

    private static int processImpactReaction(IsoGameCharacter shooter, HandWeapon weapon,
                                             IsoGameCharacter target,
                                             stgael.ballistics.BallisticVector3 point,
                                             int bodyPart) {
        BallisticsController controller = shooter.getBallisticsController();
        if (controller == null) return CombatManager.getInstance().processHit(weapon, shooter, target);
        ImpactCache cache;
        try {
            cache = ImpactCache.install(controller, target.getID(), point, bodyPart);
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return CombatManager.getInstance().processHit(weapon, shooter, target);
        }
        try {
            return CombatManager.getInstance().processHit(weapon, shooter, target);
        } finally {
            cache.restore();
        }
    }

    /** Scoped override of PZ's camera-target cache during its native hit reaction. */
    private static final class ImpactCache {
        private static final int MAX_CAMERA_TARGETS = 10;
        private final float[] current;
        private final float[] cached;
        private final int currentCount;
        private final int cachedCount;
        private final int currentSlot;
        private final int cachedSlot;
        private final float[] currentRow;
        private final float[] cachedRow;
        private final BallisticsController controller;
        private final java.lang.reflect.Field currentCountField;
        private final java.lang.reflect.Field cachedCountField;

        private ImpactCache(BallisticsController controller, int id,
                            stgael.ballistics.BallisticVector3 point, int bodyPart)
                throws ReflectiveOperationException {
            this.controller = controller;
            Class<?> type = BallisticsController.class;
            var currentField = type.getDeclaredField("ballisticsCameraTargets");
            var cachedField = type.getDeclaredField("cachedBallisticsCameraTargets");
            currentCountField = type.getDeclaredField("numberOfCameraTargets");
            cachedCountField = type.getDeclaredField("cachedNumberOfCameraTargets");
            currentField.setAccessible(true);
            cachedField.setAccessible(true);
            currentCountField.setAccessible(true);
            cachedCountField.setAccessible(true);
            current = (float[]) currentField.get(controller);
            cached = (float[]) cachedField.get(controller);
            currentCount = currentCountField.getInt(controller);
            cachedCount = cachedCountField.getInt(controller);
            currentSlot = locate(current, currentCount, id);
            cachedSlot = locate(cached, cachedCount, id);
            currentRow = row(current, currentSlot);
            cachedRow = row(cached, cachedSlot);
            write(current, currentSlot, id, point, bodyPart);
            write(cached, cachedSlot, id, point, bodyPart);
            currentCountField.setInt(controller, Math.max(currentCount,
                    Math.min(MAX_CAMERA_TARGETS, currentSlot + 1)));
            cachedCountField.setInt(controller, Math.max(cachedCount,
                    Math.min(MAX_CAMERA_TARGETS, cachedSlot + 1)));
        }

        static ImpactCache install(BallisticsController controller, int id,
                                   stgael.ballistics.BallisticVector3 point, int bodyPart)
                throws ReflectiveOperationException {
            return new ImpactCache(controller, id, point, bodyPart);
        }

        void restore() {
            int currentBase = currentSlot * 5;
            int cachedBase = cachedSlot * 5;
            System.arraycopy(currentRow, 0, current, currentBase, 5);
            System.arraycopy(cachedRow, 0, cached, cachedBase, 5);
            try {
                currentCountField.setInt(controller, currentCount);
                cachedCountField.setInt(controller, cachedCount);
            } catch (ReflectiveOperationException ignored) {
                // Values have been restored; an inaccessible count cannot be
                // repaired without retaining the controller reference.
            }
        }

        private static int locate(float[] values, int count, int id) {
            for (int i = 0; i < count; i++) {
                if ((int) values[i * 5] == id) return i;
            }
            return Math.min(count, MAX_CAMERA_TARGETS - 1);
        }

        private static float[] row(float[] values, int slot) {
            return java.util.Arrays.copyOfRange(values, slot * 5, slot * 5 + 5);
        }

        private static void write(float[] values, int slot, int id,
                                  stgael.ballistics.BallisticVector3 point, int bodyPart) {
            int base = slot * 5;
            values[base] = id;
            values[base + 1] = (float) point.x();
            values[base + 2] = (float) point.z();
            values[base + 3] = (float) point.y();
            values[base + 4] = bodyPart;
        }
    }

    private static Method rangeHitDamageMethod() {
        try {
            Method method = CombatManager.class.getDeclaredMethod("applyRangeHitLocationDamage",
                    IsoGameCharacter.class, HandWeapon.class, int.class, float.class);
            method.setAccessible(true);
            return method;
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return null;
        }
    }

    private static float applyRangeHitLocationDamage(IsoGameCharacter target, HandWeapon weapon,
                                                      int bodyPart, float rawDamage) {
        if (RANGE_HIT_DAMAGE == null) return rawDamage;
        try {
            return ((Number) RANGE_HIT_DAMAGE.invoke(CombatManager.getInstance(),
                    target, weapon, bodyPart, rawDamage)).floatValue();
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            return rawDamage;
        }
    }

    /** Damage inputs must come from the weapon/ammo policy; this class does not invent them. */
    public record DamagePlan(float baseDamage, float rangeMultiplier, boolean critical) {
        public DamagePlan {
            if (!Float.isFinite(baseDamage) || baseDamage <= 0.0f
                    || !Float.isFinite(rangeMultiplier) || rangeMultiplier < 0.0f) {
                throw new IllegalArgumentException("Damage values must be finite and non-negative");
            }
        }
    }

    public record Result(Status status, Object target, float appliedDamage,
                         int impactBodyPart, int reactionBodyPart) {}

    public enum Status {
        APPLIED,
        NOT_A_CHARACTER_HIT,
        INVALID_TARGET,
        CLIENT_NEEDS_SERVER_VALIDATION
    }
}
