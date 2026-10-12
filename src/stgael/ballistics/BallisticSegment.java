package stgael.ballistics;

/** Swept segment produced by one fixed physics sub-step. */
public record BallisticSegment(BallisticVector3 start, BallisticVector3 end,
                               double startSeconds, double endSeconds) {}
