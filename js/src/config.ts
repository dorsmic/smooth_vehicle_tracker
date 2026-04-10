/** Normalized marker anchor (e.g. Google Maps Symbol `anchor` in fraction of icon size). */
export interface VehicleAnchor {
  x: number;
  y: number;
}

/**
 * Mirrors Dart `VehicleTrackingConfig`; durations are in milliseconds for JS.
 */
export interface VehicleTrackingConfig {
  minMoveMeters: number;
  maxJumpMeters: number;
  fastJumpWindowMs: number;
  tickIntervalMs: number;
  minSpeedMps: number;
  maxSpeedMps: number;
  speedSmoothing: number;
  speedDecayPerSec: number;
  freshSseWindowMs: number;
  routeSnapMaxDistanceMeters: number;
  routeSnapReleaseDistanceMeters: number;
  segmentAngleWeight: number;
  maxSnapHeadingDeltaDeg: number;
  routeHeadingBlend: number;
  lookAheadMinMeters: number;
  lookAheadMaxMeters: number;
  lookAheadSpeedFactor: number;
  intersectionExtraLookAheadMeters: number;
  intersectionCandidateDistanceMeters: number;
  baseCorrectionFactor: number;
  aggressiveCorrectionFactor: number;
  aggressiveCorrectionDistance: number;
  correctionDecayPerTick: number;
  correctionStopDistanceMeters: number;
  stationarySpeedEpsilonMps: number;
  bearingDeadbandDeg: number;
  maxTurnRateTickDegPerSec: number;
  maxTurnRateSseDegPerSec: number;
  maxTurnRateTickOnSegmentChangeDegPerSec: number;
  maxTurnRateSseOnSegmentChangeDegPerSec: number;
  headingFreezeMoveMeters: number;
  vehicleAnchor: VehicleAnchor;
  forwardPlacementMeters: number;
}

export const defaultVehicleTrackingConfig: VehicleTrackingConfig = {
  minMoveMeters: 1.8,
  maxJumpMeters: 220.0,
  fastJumpWindowMs: 2000,
  tickIntervalMs: 60,
  minSpeedMps: 2.3,
  maxSpeedMps: 36.0,
  speedSmoothing: 0.28,
  speedDecayPerSec: 0.972,
  freshSseWindowMs: 12_000,
  routeSnapMaxDistanceMeters: 28.0,
  routeSnapReleaseDistanceMeters: 44.0,
  segmentAngleWeight: 0.38,
  maxSnapHeadingDeltaDeg: 48.0,
  routeHeadingBlend: 0.72,
  lookAheadMinMeters: 12.0,
  lookAheadMaxMeters: 45.0,
  lookAheadSpeedFactor: 1.7,
  intersectionExtraLookAheadMeters: 18.0,
  intersectionCandidateDistanceMeters: 30.0,
  baseCorrectionFactor: 0.14,
  aggressiveCorrectionFactor: 0.3,
  aggressiveCorrectionDistance: 26.0,
  correctionDecayPerTick: 0.84,
  correctionStopDistanceMeters: 2.5,
  stationarySpeedEpsilonMps: 0.35,
  bearingDeadbandDeg: 5.0,
  maxTurnRateTickDegPerSec: 18.0,
  maxTurnRateSseDegPerSec: 24.0,
  maxTurnRateTickOnSegmentChangeDegPerSec: 34.0,
  maxTurnRateSseOnSegmentChangeDegPerSec: 42.0,
  headingFreezeMoveMeters: 0.8,
  vehicleAnchor: { x: 0.5, y: 0.56 },
  forwardPlacementMeters: 1.8,
};

export function mergeVehicleTrackingConfig(
  partial?: Partial<VehicleTrackingConfig>,
): VehicleTrackingConfig {
  return { ...defaultVehicleTrackingConfig, ...partial };
}
