import 'dart:ui';

/// Tunables for [VehicleTrackingEngine], defaults optimized for **~10s between
/// server (SSE) GPS fixes** — not 1–3s. At 50–90 km/h the vehicle moves
/// ~140–250m between updates; correction, snap, and decay must close large gaps
/// without teleporting or tail-first sliding.
class VehicleTrackingConfig {
  final double minMoveMeters;
  final double maxJumpMeters;
  final Duration fastJumpWindow;
  final Duration tickInterval;
  final double minSpeedMps;
  final double maxSpeedMps;
  final double speedSmoothing;
  /// Per-second multiplier when no SSE for longer than [freshSseWindow] (unused
  /// for tick-based stale decay — see [staleSseSpeedDecayPerTick]).
  final double speedDecayPerSec;
  /// Must exceed the SSE period (e.g. 10s) so extrapolation still trusts the
  /// last fix for the full gap; here 12s avoids cutting speed mid-gap.
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
  /// Above this error (m), aggressive correction applies — 10s gaps can yield
  /// 100–250m before the next fix closes the loop.
  final double aggressiveCorrectionDistance;
  final double correctionDecayPerTick;
  final double correctionStopDistanceMeters;
  final double stationarySpeedEpsilonMps;
  final double bearingDeadbandDeg;
  final double maxTurnRateTickDegPerSec;
  /// Used on SSE-driven heading boosts (sharp turns); allows near-instant turn.
  final double maxTurnRateSseDegPerSec;
  final double maxTurnRateTickOnSegmentChangeDegPerSec;
  final double maxTurnRateSseOnSegmentChangeDegPerSec;
  final double headingFreezeMoveMeters;
  final Offset vehicleAnchor;
  final double forwardPlacementMeters;

  /// After [freshSseWindow] without SSE, multiply speed once per tick (~60ms).
  final double staleSseSpeedDecayPerTick;

  /// While still inside [freshSseWindow], floor extrapolated speed at this
  /// fraction of the last SSE-inferred target (réduit la traînée sur longs trous).
  /// Trop haut = le marqueur « fonce » tout droit avant le prochain fix (virages).
  final double extrapolationSpeedFloorFactor;

  /// Multiplicateur sur `vitesse × temps depuis dernier SSE` : distance max.
  /// le long du **dernier cap GPS** depuis le dernier fix (évite de dépasser
  /// l’intersection avant le prochain point).
  final double extrapolationAlongRaySlack;

  /// Marge minimale (m) ajoutée au plafond le long du rayon.
  final double extrapolationAlongRayMarginMeters;

  /// Plafond dur (m) sur la distance le long du rayon depuis le dernier fix.
  final double extrapolationMaxAlongMeters;

  /// Multiplicateur sur la longueur du **dernier** segment SSE (prev→fix) pour
  /// borner l’extrapolation (virages après un petit segment).
  final double extrapolationChordSlack;

  /// Si distance(track, pivot) > seuil à l’entrée virage : glisser jusqu’au pivot
  /// (cap figé, vitesse 0) avant la phase rotation. ~0,35 m ≈ toujours glisser sauf coïncidence.
  final double preRotationBlendJumpThresholdMeters;

  /// Ticks de glissement position avant le pivot (quand saut > seuil).
  final int preRotationPositionBlendTicks;

  /// Large GPS vs current speed step (m/s): skip smoothing, jump toward target.
  final double adaptiveSpeedJumpThresholdMps;

  /// First tick after such a jump uses this fraction of target speed.
  final double adaptiveSpeedJumpBlend;

  /// Segment index change + farther than this from snap → instant jump (no lateral lerp).
  final double segmentJumpSnapMeters;

  /// Ticks at full aggressive correction after a segment change (e.g. 8×60ms).
  final int repositionBoostTicks;

  /// GPS vs polyline heading beyond this (deg) → trust GPS heading.
  final double gpsHeadingWinsOverPolylineDeg;

  /// Si false, chaque [VehicleTrackingEngine.tick] peut déclencher un repaint du marqueur (Flutter).
  /// Si true (défaut), [VehicleTrackingEngine.shouldRepaintMarker] limite la fréquence pour éviter le clignotement du [GoogleMap].
  final bool markerVisualThrottleEnabled;

  /// Intervalle minimum entre deux « autorisations » de rebuild du marqueur côté UI.
  final Duration markerVisualMinInterval;

  /// Déplacement min. du point de rendu vs dernier affiché pour considérer un changement utile.
  final double markerVisualMinMoveMeters;

  /// Delta de cap min. (deg) pour la même chose.
  final double markerVisualMinBearingDeltaDeg;

  /// Au-delà de cet écart (cap actuel vs nouveau cap GPS), phase « pivoter puis avancer » (Bolt/Uber).
  final double rotationEnterThresholdDeg;

  /// Fin de rotation lorsque le cap est à ce delta (deg) de la cible.
  final double rotationCompleteThresholdDeg;

  /// Pas max de rotation par tick (~60 ms), en degrés.
  final double rotationMaxStepDegPerTick;

  /// Facteur min. sur ce pas (courbe sinus : début/fin de pivot plus doux, milieu plus vif).
  final double rotationEaseMinFactor;

  /// Après un pivot, nombre de ticks pour interpoler la position vers le fix GPS
  /// (évite le saut visible). ~8×60ms ≈ 480ms.
  final int postRotationSnapBlendTicks;

  /// (Réservé / compat.) Autrefois snap direct post-pivot ; le moteur lisse toujours désormais.
  final double postRotationSnapInstantBelowMeters;

  /// 2ᵉ fix GPS : interpolation position + cap sur la corde (évite le saut pleine distance).
  final int startupPositionBlendTicks;

  /// En dessous : alignement direct sans blend (mètres).
  final double startupSnapInstantBelowMeters;

  const VehicleTrackingConfig({
    this.minMoveMeters = 1.8,
    // 10s × ~30 m/s ≈ 300m max plausible jump; tighter window rejects only spikes.
    this.maxJumpMeters = 300.0,
    this.fastJumpWindow = const Duration(seconds: 2),
    this.tickInterval = const Duration(milliseconds: 60),
    this.minSpeedMps = 2.3,
    // ~90 km/h ceiling for motorway extrapolation.
    this.maxSpeedMps = 40.0,
    // Slightly higher smoothing gain so the marker reaches inferred speed faster on 10s cadence.
    this.speedSmoothing = 0.35,
    this.speedDecayPerSec = 0.972,
    this.freshSseWindow = const Duration(seconds: 12),
    // Urban ~6–8m lanes: keep snap tight so the marker does not sit in buildings.
    this.routeSnapMaxDistanceMeters = 20.0,
    this.routeSnapReleaseDistanceMeters = 44.0,
    /// Penalise parallel streets one block away; pairs with heading-first pick at intersections.
    this.segmentAngleWeight = 0.4,
    this.maxSnapHeadingDeltaDeg = 48.0,
    this.routeHeadingBlend = 0.72,
    this.lookAheadMinMeters = 15.0,
    // Longer lookahead on fast roads between 10s fixes.
    this.lookAheadMaxMeters = 80.0,
    this.lookAheadSpeedFactor = 3.0,
    this.intersectionExtraLookAheadMeters = 18.0,
    this.intersectionCandidateDistanceMeters = 30.0,
    this.baseCorrectionFactor = 0.06,
    this.aggressiveCorrectionFactor = 0.15,
    this.aggressiveCorrectionDistance = 40.0,
    // Slower decay so correction survives across many 60ms ticks during a 10s gap.
    this.correctionDecayPerTick = 0.92,
    this.correctionStopDistanceMeters = 2.5,
    this.stationarySpeedEpsilonMps = 0.35,
    this.bearingDeadbandDeg = 2.5,
    // ~3.6°/tick at 60ms in normal driving.
    this.maxTurnRateTickDegPerSec = 60.0,
    this.maxTurnRateSseDegPerSec = 180.0,
    this.maxTurnRateTickOnSegmentChangeDegPerSec = 120.0,
    this.maxTurnRateSseOnSegmentChangeDegPerSec = 42.0,
    this.headingFreezeMoveMeters = 0.8,
    this.vehicleAnchor = const Offset(0.5, 0.56),
    this.forwardPlacementMeters = 1.8,
    this.staleSseSpeedDecayPerTick = 0.97,
    this.extrapolationSpeedFloorFactor = 0.44,
    this.extrapolationAlongRaySlack = 0.88,
    this.extrapolationAlongRayMarginMeters = 18.0,
    this.extrapolationMaxAlongMeters = 72.0,
    this.extrapolationChordSlack = 1.1,
    this.preRotationBlendJumpThresholdMeters = 0.35,
    this.preRotationPositionBlendTicks = 16,
    this.adaptiveSpeedJumpThresholdMps = 8.0,
    this.adaptiveSpeedJumpBlend = 0.85,
    /// Lateral jump threshold at turns (m); above this, instant snap is mandatory.
    this.segmentJumpSnapMeters = 6.0,
    /// Strong correction after a turn so lane alignment recovers before the next SSE (~10s).
    this.repositionBoostTicks = 10,
    this.gpsHeadingWinsOverPolylineDeg = 60.0,
    this.markerVisualThrottleEnabled = true,
    this.markerVisualMinInterval = const Duration(milliseconds: 100),
    this.markerVisualMinMoveMeters = 0.5,
    this.markerVisualMinBearingDeltaDeg = 2.0,
    this.rotationEnterThresholdDeg = 25.0,
    this.rotationCompleteThresholdDeg = 8.0,
    this.rotationMaxStepDegPerTick = 12.0,
    this.rotationEaseMinFactor = 0.32,
    this.postRotationSnapBlendTicks = 12,
    this.postRotationSnapInstantBelowMeters = 2.0,
    this.startupPositionBlendTicks = 22,
    this.startupSnapInstantBelowMeters = 2.5,
  });
}
