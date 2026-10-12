package stgael.ballistics;

import java.util.Objects;

/** First world contact along a swept projectile segment. Target is owned by the PZ adapter. */
public record BallisticCollision(Kind kind, BallisticVector3 position, Object target) {
    public BallisticCollision {
        Objects.requireNonNull(kind, "kind");
        Objects.requireNonNull(position, "position");
    }

    public enum Kind { CHARACTER, WINDOW, VEHICLE, WORLD }
}
