package stgael.pz;

import zombie.iso.Vector3;
import stgael.ballistics.BallisticVector3;

/** Converts PZ's tile-based coordinates to the independent engine's metre axes. */
public final class PzBallisticCoordinates {
    /** A map square is treated as one metre horizontally; kept configurable for calibration. */
    private final double metresPerTile;
    /** Vertical spacing between PZ levels used by the native shot bridge. */
    private final double metresPerLevel;

    public PzBallisticCoordinates(double metresPerTile, double metresPerLevel) {
        if (!Double.isFinite(metresPerTile) || metresPerTile <= 0.0
                || !Double.isFinite(metresPerLevel) || metresPerLevel <= 0.0) {
            throw new IllegalArgumentException("World scale values must be finite and positive");
        }
        this.metresPerTile = metresPerTile;
        this.metresPerLevel = metresPerLevel;
    }

    public BallisticVector3 positionToMetres(Vector3 pzPosition) {
        return new BallisticVector3(pzPosition.x * metresPerTile,
                pzPosition.y * metresPerTile, pzPosition.z * metresPerLevel);
    }

    /** Convert PZ's normalized tile-axis direction while preserving physical elevation. */
    public BallisticVector3 directionToMetres(Vector3 pzDirection) {
        return new BallisticVector3(pzDirection.x * metresPerTile,
                pzDirection.y * metresPerTile, pzDirection.z * metresPerLevel).normalized();
    }

    public int tileX(BallisticVector3 metres) { return (int) Math.floor(metres.x() / metresPerTile); }
    public int tileY(BallisticVector3 metres) { return (int) Math.floor(metres.y() / metresPerTile); }
    public int level(BallisticVector3 metres) { return (int) Math.floor(metres.z() / metresPerLevel); }

    public BallisticVector3 collisionToMetres(Vector3 pzPosition) {
        return positionToMetres(pzPosition);
    }

    public double metresPerTile() { return metresPerTile; }
    public double metresPerLevel() { return metresPerLevel; }
}
