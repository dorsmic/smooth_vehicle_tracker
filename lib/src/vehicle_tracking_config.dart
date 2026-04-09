import 'dart:ui';

class VehicleTrackingConfig {
  final double minMoveMeters;
  final double maxJumpMeters;
  final Duration fastJumpWindow;
  final Duration tickInterval;
  final double minSpeedMps;
  final double maxSpeedMps;
  final double speedSmoothing;
  final double speedDecayPerSec;
  final Duration freshSseWindow;
  final double routeSnapMaxDistanceMeters;
  final double routeSnapReleaseDistanceMeters;
  final double segmentAngleWeight;
  final double maxSnapHeadingDeltaDeg;
  final double routeHeadingBlend;
  final double lookAheadMinMeters;
  final double lookAheadMaxMeters;
  final double lookAheadSpeedFactor;
  final double intersectionExtraLookAheadMeters;
  final double intersectionCandidateDistanceMeters;
  final double baseCorrectionFactor;
  final double aggressiveCorrectionFactor;
  final double aggressiveCorrectionDistance;
  final double correctionDecayPerTick;
  final double correctionStopDistanceMeters;
  final double stationarySpeedEpsilonMps;
  final double bearingDeadbandDeg;
  final double maxTurnRateTickDegPerSec;
  final double maxTurnRateSseDegPerSec;
  final double maxTurnRateTickOnSegmentChangeDegPerSec;
  final double maxTurnRateSseOnSegmentChangeDegPerSec;
  final double headingFreezeMoveMeters;
  final Offset vehicleAnchor;
  final double forwardPlacementMeters;

  const VehicleTrackingConfig({
    this.minMoveMeters = 1.8,
    this.maxJumpMeters = 220.0,
    this.fastJumpWindow = const Duration(seconds: 2),
    this.tickInterval = const Duration(milliseconds: 60),
    this.minSpeedMps = 2.3,
    this.maxSpeedMps = 36.0,
    this.speedSmoothing = 0.28,
    this.speedDecayPerSec = 0.972,
    this.freshSseWindow = const Duration(seconds: 12),
    this.routeSnapMaxDistanceMeters = 28.0,
    this.routeSnapReleaseDistanceMeters = 44.0,
    this.segmentAngleWeight = 0.38,
    this.maxSnapHeadingDeltaDeg = 48.0,
    this.routeHeadingBlend = 0.72,
    this.lookAheadMinMeters = 12.0,
    this.lookAheadMaxMeters = 45.0,
    this.lookAheadSpeedFactor = 1.7,
    this.intersectionExtraLookAheadMeters = 18.0,
    this.intersectionCandidateDistanceMeters = 30.0,
    this.baseCorrectionFactor = 0.14,
    this.aggressiveCorrectionFactor = 0.30,
    this.aggressiveCorrectionDistance = 26.0,
    this.correctionDecayPerTick = 0.84,
    this.correctionStopDistanceMeters = 2.5,
    this.stationarySpeedEpsilonMps = 0.35,
    this.bearingDeadbandDeg = 5.0,
    this.maxTurnRateTickDegPerSec = 18.0,
    this.maxTurnRateSseDegPerSec = 24.0,
    this.maxTurnRateTickOnSegmentChangeDegPerSec = 34.0,
    this.maxTurnRateSseOnSegmentChangeDegPerSec = 42.0,
    this.headingFreezeMoveMeters = 0.8,
    this.vehicleAnchor = const Offset(0.5, 0.56),
    this.forwardPlacementMeters = 1.8,
  });
}
