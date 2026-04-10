import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'vehicle_tracking_config.dart';
import 'vehicle_tracking_math.dart';
import 'vehicle_tracking_models.dart';

enum _MarkerPhase {
  /// Avance + correction habituelles.
  moving,

  /// Cap uniquement : pas de translation (pivot sur place puis lissage vers le fix).
  rotating,
}

enum _SnapBlendKind {
  none,
  /// 1ʳᵉ→2ᵉ fix : corde + cap sans téléport.
  startup,
  /// Approche du coin cap figé.
  preRotation,
  /// Après pivot vers le fix GPS.
  postRotation,
}

/// Dead reckoning **GPS-first** : fixes SSE successifs définissent vitesse et cap.
/// Comportement type Bolt/Uber : au changement de direction notable, **pivoter puis avancer**
/// (pas de translation + rotation simultanées).
/// [polyline] est ignoré (affichage carte uniquement).
class VehicleTrackingEngine {
  final VehicleTrackingConfig config;

  VehicleTrackingState _state;
  DateTime? _lastTickAt;
  LatLng? _lastRawSsePosition;
  LatLng? _correctionTarget;
  double _correctionWeight = 0.0;
  double _targetSpeedMps = 0.0;

  int _repositionBoostFrames = 0;
  int _highSpeedBoostFrames = 0;

  bool _applyAdaptiveSpeedJumpNextTick = false;
  double? _lastGpsHeading;

  _MarkerPhase _phase = _MarkerPhase.moving;
  double _rotationTargetBearing = 0.0;
  LatLng? _pendingSnapPosition;

  /// Glissement post-pivot ou **pré-pivot** (rapproche du segment sans téléport).
  int _snapBlendRemaining = 0;
  int _snapBlendDurationTicks = 0;
  LatLng? _snapBlendStart;
  LatLng? _snapBlendEnd;
  _SnapBlendKind _snapBlendKind = _SnapBlendKind.none;
  double? _preRotateBearingLock;
  double? _deferredRotationTargetBearing;
  LatLng? _deferredPendingSnap;
  double _startupBearingFrom = 0.0;
  double _startupBearingTo = 0.0;

  /// Longueur du dernier segment SSE (prev→fix), pour borner l’extrapolation.
  double _lastSseChordMeters = 90.0;

  /// Après le tout premier fix (sans prev), le **deuxième** fix aligne le cap sans phase rotation
  /// (évite saut 0° → segment + pivot artificiel au démarrage).
  bool _needsSecondFixHeadingAlign = false;

  /// Amplitude initiale du pivot (pour adoucir début/fin de rotation).
  double? _rotationInitialDeltaAbs;

  /// Dernier rendu « poussé » vers la carte — pour [shouldRepaintMarker] (anti-clignotement).
  LatLng? _lastEmittedRenderPosition;
  double _lastEmittedBearing = 0;
  DateTime? _lastVisualEmitAt;
  bool _visualRepaintPending = false;
  bool _shouldRepaintMarker = false;

  VehicleTrackingEngine({
    required this.config,
    LatLng? initialPosition,
  }) : _state = VehicleTrackingState.initial(initialPosition);

  VehicleTrackingState get state => _state;

  /// Mis à jour à chaque [tick] : indique si l’app doit appeler `setState` pour rafraîchir le marqueur.
  bool get shouldRepaintMarker => _shouldRepaintMarker;

  void setInitialPosition(LatLng? position) {
    _resetVisualThrottleBaseline();
    _resetRotationState();
    _needsSecondFixHeadingAlign = false;
    _rotationInitialDeltaAbs = null;
    _state = _state.copyWith(
      trackPosition: position,
      renderPosition: position,
    );
    _lastRawSsePosition = position;
  }

  void _resetVisualThrottleBaseline() {
    _lastEmittedRenderPosition = null;
    _lastEmittedBearing = 0;
    _lastVisualEmitAt = null;
    _visualRepaintPending = false;
    _shouldRepaintMarker = false;
  }

  void _resetRotationState() {
    _phase = _MarkerPhase.moving;
    _pendingSnapPosition = null;
    _cancelSnapBlend();
  }

  void _cancelSnapBlend() {
    _snapBlendRemaining = 0;
    _snapBlendDurationTicks = 0;
    _snapBlendStart = null;
    _snapBlendEnd = null;
    _snapBlendKind = _SnapBlendKind.none;
    _preRotateBearingLock = null;
    _deferredRotationTargetBearing = null;
    _deferredPendingSnap = null;
  }

  /// Contourne le throttle visuel une frame (virages / transitions).
  void _forceImmediateMarkerRepaint() {
    _visualRepaintPending = true;
    _lastVisualEmitAt = null;
  }

  void onSsePosition(LatLng newPos, {DateTime? now, List<LatLng>? polyline}) {
    final ts = now ?? DateTime.now();
    final prevRaw = _lastRawSsePosition;

    if (prevRaw == null) {
      _lastRawSsePosition = newPos;
      _needsSecondFixHeadingAlign = true;
      // Pas de forwardPlacement : le cap n’est pas encore fiable (souvent 0°) → évite le 1er saut.
      _state = _state.copyWith(
        trackPosition: newPos,
        renderPosition: newPos,
        speedMps: 0.0,
        lastSseAt: ts,
      );
      _forceImmediateMarkerRepaint();
      return;
    }

    final movedMeters = VehicleTrackingMath.distanceMeters(prevRaw, newPos);
    final elapsed =
        _state.lastSseAt == null ? const Duration(seconds: 1) : ts.difference(_state.lastSseAt!);

    if (movedMeters < config.minMoveMeters) {
      _targetSpeedMps = 0.0;
      _lastRawSsePosition = newPos;
      if (_needsSecondFixHeadingAlign) {
        _needsSecondFixHeadingAlign = false;
      }
      _state = _state.copyWith(speedMps: 0.0, lastSseAt: ts);
      return;
    }

    if (elapsed <= config.fastJumpWindow && movedMeters > config.maxJumpMeters) {
      return;
    }

    final dtSec = _elapsedSecForSse(elapsed);
    final speedMps = (movedMeters / dtSec).clamp(0.0, config.maxSpeedMps);
    _targetSpeedMps = speedMps < config.stationarySpeedEpsilonMps
        ? 0.0
        : speedMps.clamp(config.minSpeedMps, config.maxSpeedMps);

    final rawHeading = _bearingBetween(prevRaw, newPos);
    final headingDelta = VehicleTrackingMath.angleDeltaAbs(rawHeading, _state.bearing);

    if ((_targetSpeedMps - _state.speedMps).abs() > config.adaptiveSpeedJumpThresholdMps) {
      _applyAdaptiveSpeedJumpNextTick = true;
    }

    if (_targetSpeedMps > 15.0) {
      _highSpeedBoostFrames = 8;
    }

    _lastGpsHeading = rawHeading;
    _lastSseChordMeters = movedMeters;

    if (_snapBlendRemaining > 0 && _snapBlendKind == _SnapBlendKind.startup) {
      _snapBlendEnd = newPos;
      _startupBearingTo = rawHeading;
      _lastRawSsePosition = newPos;
      _state = _state.copyWith(
        lastSseAt: ts,
        speedMps: _targetSpeedMps,
        segmentIndex: 0,
        isIntersectionMode: false,
      );
      return;
    }

    // 2ᵉ fix : blend le long de la corde + cap (évite téléport P0→P1 d’un coup).
    if (_needsSecondFixHeadingAlign) {
      _needsSecondFixHeadingAlign = false;
      _cancelSnapBlend();
      _lastRawSsePosition = newPos;
      _phase = _MarkerPhase.moving;
      _rotationInitialDeltaAbs = null;
      final from = _state.trackPosition ?? newPos;
      final chord = VehicleTrackingMath.distanceMeters(from, newPos);
      if (chord <= config.startupSnapInstantBelowMeters) {
        _correctionTarget = newPos;
        _correctionWeight = 1.0;
        _state = _state.copyWith(
          trackPosition: newPos,
          renderPosition: _offsetForwardByMeters(
            newPos,
            rawHeading,
            config.forwardPlacementMeters,
          ),
          bearing: rawHeading,
          speedMps: _targetSpeedMps,
          lastSseAt: ts,
          segmentIndex: 0,
          isIntersectionMode: false,
        );
      } else {
        _snapBlendStart = from;
        _snapBlendEnd = newPos;
        _startupBearingFrom = _state.bearing;
        _startupBearingTo = rawHeading;
        _snapBlendDurationTicks =
            math.max(1, config.startupPositionBlendTicks);
        _snapBlendRemaining = _snapBlendDurationTicks;
        _snapBlendKind = _SnapBlendKind.startup;
        _correctionTarget = null;
        _correctionWeight = 0.0;
        _state = _state.copyWith(
          lastSseAt: ts,
          speedMps: _targetSpeedMps,
          segmentIndex: 0,
          isIntersectionMode: false,
        );
      }
      _forceImmediateMarkerRepaint();
      return;
    }

    // Nouveau fix pendant une rotation : mettre à jour la cible et le saut, sans repartir à zéro.
    if (_phase == _MarkerPhase.rotating) {
      _rotationTargetBearing = rawHeading;
      _pendingSnapPosition = newPos;
      _rotationInitialDeltaAbs = VehicleTrackingMath.angleDeltaAbs(
        _state.bearing,
        rawHeading,
      );
      _correctionTarget = null;
      _correctionWeight = 0.0;
      _lastRawSsePosition = newPos;
      _state = _state.copyWith(
        lastSseAt: ts,
        speedMps: _targetSpeedMps,
        segmentIndex: 0,
        isIntersectionMode: false,
      );
      return;
    }

    // À l’arrêt : pas de phase rotation — cap + position alignés directement.
    if (_targetSpeedMps <= config.stationarySpeedEpsilonMps) {
      _cancelSnapBlend();
      _correctionTarget = newPos;
      _correctionWeight = 1.0;
      _lastRawSsePosition = newPos;
      _state = _state.copyWith(
        trackPosition: newPos,
        renderPosition: _offsetForwardByMeters(
          newPos,
          rawHeading,
          config.forwardPlacementMeters,
        ),
        bearing: rawHeading,
        speedMps: 0.0,
        lastSseAt: ts,
        segmentIndex: 0,
        isIntersectionMode: false,
      );
      return;
    }

    if (_snapBlendRemaining > 0 && _snapBlendKind == _SnapBlendKind.preRotation) {
      final cur = _state.trackPosition;
      final anchored =
          cur != null ? _closestPointOnSegmentClamp(cur, prevRaw, newPos) : newPos;
      _snapBlendEnd = anchored;
      _deferredRotationTargetBearing = rawHeading;
      _deferredPendingSnap = newPos;
      _lastRawSsePosition = newPos;
      _state = _state.copyWith(
        lastSseAt: ts,
        speedMps: _targetSpeedMps,
        segmentIndex: 0,
        isIntersectionMode: false,
      );
      return;
    }

    if (_snapBlendRemaining > 0 && _snapBlendKind == _SnapBlendKind.postRotation) {
      _snapBlendEnd = newPos;
    }

    // Virage significatif : si l’extrapolation a trop dépassé, glisser vers le pivot puis pivoter
    // (sinon téléport brutal au SSE). Sinon pivot immédiat sur le point projeté.
    if (headingDelta > config.rotationEnterThresholdDeg) {
      _cancelSnapBlend();
      final t = _state.trackPosition;
      final anchored =
          t != null ? _closestPointOnSegmentClamp(t, prevRaw, newPos) : null;
      final pivot = anchored ?? t;
      final jumpDist =
          (t != null && pivot != null) ? VehicleTrackingMath.distanceMeters(t, pivot) : 0.0;

      _correctionTarget = null;
      _correctionWeight = 0.0;
      _lastRawSsePosition = newPos;

      if (jumpDist > config.preRotationBlendJumpThresholdMeters &&
          t != null &&
          pivot != null) {
        _snapBlendStart = t;
        _snapBlendEnd = pivot;
        _snapBlendDurationTicks =
            math.max(1, config.preRotationPositionBlendTicks);
        _snapBlendRemaining = _snapBlendDurationTicks;
        _snapBlendKind = _SnapBlendKind.preRotation;
        _preRotateBearingLock = _state.bearing;
        _deferredRotationTargetBearing = rawHeading;
        _deferredPendingSnap = newPos;
        _phase = _MarkerPhase.moving;
        _state = _state.copyWith(
          lastSseAt: ts,
          speedMps: _targetSpeedMps,
          segmentIndex: 0,
          isIntersectionMode: false,
        );
        _forceImmediateMarkerRepaint();
        return;
      }

      _phase = _MarkerPhase.rotating;
      _rotationTargetBearing = rawHeading;
      _pendingSnapPosition = newPos;
      _rotationInitialDeltaAbs = VehicleTrackingMath.angleDeltaAbs(
        _state.bearing,
        rawHeading,
      );
      _snapBlendKind = _SnapBlendKind.none;
      _preRotateBearingLock = null;
      _deferredRotationTargetBearing = null;
      _deferredPendingSnap = null;
      _state = _state.copyWith(
        trackPosition: pivot,
        renderPosition: pivot == null
            ? _state.renderPosition
            : _offsetForwardByMeters(
                pivot,
                _state.bearing,
                config.forwardPlacementMeters,
              ),
        lastSseAt: ts,
        speedMps: _targetSpeedMps,
        segmentIndex: 0,
        isIntersectionMode: false,
      );
      _forceImmediateMarkerRepaint();
      return;
    }

    _correctionTarget = newPos;
    _correctionWeight = 1.0;
    _lastRawSsePosition = newPos;
    _state = _state.copyWith(
      segmentIndex: 0,
      isIntersectionMode: false,
      lastSseAt: ts,
    );
  }

  VehicleTrackingState tick({DateTime? now, List<LatLng>? polyline}) {
    final ts = now ?? DateTime.now();
    final track = _state.trackPosition;
    if (track == null) {
      _shouldRepaintMarker = false;
      return _state;
    }

    final dt = ts.difference(_lastTickAt ?? ts);
    _lastTickAt = ts;
    final dtSec = _elapsedSecForTick(dt);

    if (_phase == _MarkerPhase.rotating) {
      return _tickRotatingPhase(ts, dtSec, track);
    }

    if (_snapBlendRemaining > 0 && _snapBlendStart != null && _snapBlendEnd != null) {
      return _tickSnapBlendPhase(ts);
    }

    final lastSse = _state.lastSseAt;
    final withinFresh = lastSse != null && ts.difference(lastSse) <= config.freshSseWindow;
    final staleSse = lastSse == null || ts.difference(lastSse) > config.freshSseWindow;

    double desiredSpeed;
    if (staleSse) {
      desiredSpeed = (_state.speedMps * config.staleSseSpeedDecayPerTick).clamp(0.0, config.maxSpeedMps);
    } else {
      desiredSpeed = _targetSpeedMps.clamp(0.0, config.maxSpeedMps);
    }

    var currentSpeed = _state.speedMps;
    if (_applyAdaptiveSpeedJumpNextTick && withinFresh) {
      currentSpeed = desiredSpeed * config.adaptiveSpeedJumpBlend;
      _applyAdaptiveSpeedJumpNextTick = false;
    } else {
      currentSpeed = currentSpeed + (desiredSpeed - currentSpeed) * config.speedSmoothing;
    }

    if (withinFresh &&
        _targetSpeedMps > config.stationarySpeedEpsilonMps &&
        desiredSpeed > config.stationarySpeedEpsilonMps) {
      currentSpeed = math.max(
        currentSpeed,
        _targetSpeedMps * config.extrapolationSpeedFloorFactor,
      );
    }

    if (!withinFresh && currentSpeed < config.stationarySpeedEpsilonMps) {
      currentSpeed = 0.0;
    }

    currentSpeed = currentSpeed.clamp(0.0, config.maxSpeedMps);

    final movedDist = currentSpeed * dtSec;
    final movedDistForFreeze = movedDist;

    var headingTarget = _lastGpsHeading ?? _state.bearing;
    if (movedDistForFreeze <= config.headingFreezeMoveMeters && _correctionWeight < 0.05) {
      headingTarget = _state.bearing;
    }

    // Cap d’abord (icône = direction de déplacement), puis translation le long de ce cap.
    final bearing = _smoothBearingLimited(
      current: _state.bearing,
      target: headingTarget,
      alpha: _adaptiveHeadingAlpha(currentSpeed),
      dtSec: dtSec,
      maxTurnRateDegPerSec: config.maxTurnRateTickDegPerSec,
      deadbandDeg: config.bearingDeadbandDeg,
    );

    final advancedPos = movedDist > 0
        ? _offsetForwardByMeters(track, bearing, movedDist)
        : track;

    var logical = advancedPos;

    final cTarget = _correctionTarget;
    final bool boostReposition = _repositionBoostFrames > 0;
    if (cTarget != null && (boostReposition || _correctionWeight > 0.001)) {
      final err = VehicleTrackingMath.distanceMeters(logical, cTarget);
      final bool aggressive = err > config.aggressiveCorrectionDistance ||
          _highSpeedBoostFrames > 0 ||
          boostReposition;

      var factor = aggressive ? config.aggressiveCorrectionFactor : config.baseCorrectionFactor;
      if (boostReposition) {
        factor = config.aggressiveCorrectionFactor;
      }

      final toCorr = _bearingBetween(logical, cTarget);
      final align = VehicleTrackingMath.angleDeltaAbs(toCorr, bearing);
      var t = (factor * (boostReposition ? 1.0 : _correctionWeight)).clamp(0.0, 0.5);

      if (align > 90.0) {
        t *= 0.15;
      }

      logical = _lerpLatLng(logical, cTarget, t);

      if (boostReposition) {
        _repositionBoostFrames--;
      } else {
        _correctionWeight *= config.correctionDecayPerTick;
      }

      if (err <= config.correctionStopDistanceMeters ||
          (!boostReposition && _correctionWeight <= 0.01)) {
        _correctionTarget = null;
        _correctionWeight = 0.0;
      }
    } else {
      if (boostReposition) {
        _repositionBoostFrames--;
      }
    }

    if (_highSpeedBoostFrames > 0) {
      _highSpeedBoostFrames--;
    }

    if (withinFresh && _lastGpsHeading != null) {
      logical = _clampAlongLastHeadingRay(logical, ts);
    }

    final render = _offsetForwardByMeters(
      logical,
      bearing,
      config.forwardPlacementMeters,
    );
    _state = _state.copyWith(
      trackPosition: logical,
      renderPosition: render,
      bearing: bearing,
      speedMps: currentSpeed,
      segmentIndex: 0,
    );
    _shouldRepaintMarker = _computeVisualRepaint(ts);
    return _state;
  }

  /// Pivot seul : pas d’avance le long du trajet pendant la rotation.
  VehicleTrackingState _tickRotatingPhase(DateTime ts, double dtSec, LatLng frozenTrack) {
    final remaining = _signedAngleDeltaDeg(_state.bearing, _rotationTargetBearing);
    final remAbs = remaining.abs();
    _rotationInitialDeltaAbs ??=
        remAbs.clamp(config.rotationCompleteThresholdDeg + 0.1, 180.0);
    final startAbs = _rotationInitialDeltaAbs!.clamp(4.0, 180.0);
    final u = 1.0 - (remAbs / startAbs).clamp(0.0, 1.0);
    final stepScale = config.rotationEaseMinFactor +
        (1.0 - config.rotationEaseMinFactor) * math.sin(u * math.pi);
    final maxStep = config.rotationMaxStepDegPerTick * stepScale;
    final step = remaining.clamp(-maxStep, maxStep);
    final newBearing = _normalizeBearing(_state.bearing + step);

    final render = _offsetForwardByMeters(
      frozenTrack,
      newBearing,
      config.forwardPlacementMeters,
    );
    _state = _state.copyWith(
      trackPosition: frozenTrack,
      renderPosition: render,
      bearing: newBearing,
      speedMps: 0.0,
      segmentIndex: 0,
    );

    if (VehicleTrackingMath.angleDeltaAbs(newBearing, _rotationTargetBearing) <=
        config.rotationCompleteThresholdDeg) {
      _phase = _MarkerPhase.moving;
      _rotationInitialDeltaAbs = null;
      final pending = _pendingSnapPosition;
      _pendingSnapPosition = null;
      if (pending != null) {
        final dist = VehicleTrackingMath.distanceMeters(frozenTrack, pending);
        _snapBlendStart = frozenTrack;
        _snapBlendEnd = pending;
        _snapBlendDurationTicks = math.max(
          config.postRotationSnapBlendTicks,
          math.min(32, (dist / 4.5).ceil() + 10),
        );
        _snapBlendRemaining = _snapBlendDurationTicks;
        _snapBlendKind = _SnapBlendKind.postRotation;
        _repositionBoostFrames =
            dist > 14.0 ? math.min(6, config.repositionBoostTicks) : 0;
      }
      _forceImmediateMarkerRepaint();
    }

    _shouldRepaintMarker = _computeVisualRepaint(ts);
    return _state;
  }

  /// Translation douce : démarrage, pré-pivot, post-pivot.
  VehicleTrackingState _tickSnapBlendPhase(DateTime ts) {
    final start = _snapBlendStart!;
    final end = _snapBlendEnd!;
    final total = math.max(1, _snapBlendDurationTicks);
    final stepIndex = total - _snapBlendRemaining + 1;
    var uLinear = (stepIndex / total).clamp(0.0, 1.0);
    final uPos = _easeOutCubic(uLinear);
    final logical = _lerpLatLng(start, end, uPos);

    final kindThisTick = _snapBlendKind;

    late final double bearing;
    late final double currentSpeed;
    switch (kindThisTick) {
      case _SnapBlendKind.startup:
        bearing = _lerpBearing(_startupBearingFrom, _startupBearingTo, uLinear);
        currentSpeed = 0.0;
        break;
      case _SnapBlendKind.preRotation:
        bearing = _preRotateBearingLock ?? _state.bearing;
        currentSpeed = 0.0;
        break;
      case _SnapBlendKind.postRotation:
        bearing = _lastGpsHeading ?? _state.bearing;
        currentSpeed = (_targetSpeedMps * uPos).clamp(0.0, config.maxSpeedMps);
        break;
      case _SnapBlendKind.none:
        bearing = _lastGpsHeading ?? _state.bearing;
        currentSpeed = 0.0;
        break;
    }

    _snapBlendRemaining--;
    final blendJustFinished = _snapBlendRemaining <= 0;
    if (blendJustFinished) {
      _snapBlendStart = null;
      _snapBlendEnd = null;
      _snapBlendDurationTicks = 0;
      if (kindThisTick == _SnapBlendKind.preRotation) {
        _phase = _MarkerPhase.rotating;
        _rotationTargetBearing =
            _deferredRotationTargetBearing ?? _lastGpsHeading ?? _state.bearing;
        _pendingSnapPosition = _deferredPendingSnap;
        _deferredRotationTargetBearing = null;
        _deferredPendingSnap = null;
        _preRotateBearingLock = null;
      } else if (kindThisTick == _SnapBlendKind.startup) {
        _correctionTarget = end;
        _correctionWeight = 1.0;
      }
      _snapBlendKind = _SnapBlendKind.none;
      _forceImmediateMarkerRepaint();
    }

    final render = _offsetForwardByMeters(
      logical,
      bearing,
      config.forwardPlacementMeters,
    );
    _state = _state.copyWith(
      trackPosition: logical,
      renderPosition: render,
      bearing: bearing,
      speedMps: currentSpeed,
      segmentIndex: 0,
    );
    _shouldRepaintMarker = _computeVisualRepaint(ts);
    return _state;
  }

  double _lerpBearing(double fromDeg, double toDeg, double t) {
    final d = _signedAngleDeltaDeg(fromDeg, toDeg);
    return _normalizeBearing(fromDeg + d * t.clamp(0.0, 1.0));
  }

  double _easeOutCubic(double t) {
    t = t.clamp(0.0, 1.0);
    final inv = 1.0 - t;
    return 1.0 - inv * inv * inv;
  }

  /// Plus court chemin signé dans (-180, 180].
  double _signedAngleDeltaDeg(double fromDeg, double toDeg) {
    var d = toDeg - fromDeg;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  bool _computeVisualRepaint(DateTime now) {
    final rp = _state.renderPosition;
    if (rp == null) return false;
    if (!config.markerVisualThrottleEnabled) {
      return true;
    }
    // Pivot / lissage post-virage : pas de throttle (évite sauts d’icône).
    if (_phase == _MarkerPhase.rotating || _snapBlendRemaining > 0) {
      _lastEmittedRenderPosition = rp;
      _lastEmittedBearing = _state.bearing;
      _lastVisualEmitAt = now;
      return true;
    }
    final moved = _lastEmittedRenderPosition == null
        ? double.infinity
        : VehicleTrackingMath.distanceMeters(_lastEmittedRenderPosition!, rp);
    final bd = VehicleTrackingMath.angleDeltaAbs(_lastEmittedBearing, _state.bearing);
    final meaningful = moved >= config.markerVisualMinMoveMeters ||
        bd >= config.markerVisualMinBearingDeltaDeg;
    if (meaningful) {
      _visualRepaintPending = true;
    }
    if (!_visualRepaintPending) {
      return false;
    }
    final allow = _lastVisualEmitAt == null ||
        now.difference(_lastVisualEmitAt!) >= config.markerVisualMinInterval;
    if (!allow) {
      return false;
    }
    _visualRepaintPending = false;
    _lastEmittedRenderPosition = rp;
    _lastEmittedBearing = _state.bearing;
    _lastVisualEmitAt = now;
    return true;
  }

  double _adaptiveHeadingAlpha(double speedMps) {
    if (speedMps < 2) return 0.06;
    if (speedMps < 8) return 0.09;
    if (speedMps < 18) return 0.13;
    return 0.16;
  }

  double _smoothBearingLimited({
    required double current,
    required double target,
    required double alpha,
    required double dtSec,
    required double maxTurnRateDegPerSec,
    required double deadbandDeg,
  }) {
    final delta = (((target - current) + 540) % 360) - 180;
    if (delta.abs() <= deadbandDeg) return current;
    final wanted = delta * alpha;
    final maxStep = (maxTurnRateDegPerSec * dtSec).clamp(0.0, 18.0);
    final step = wanted.clamp(-maxStep, maxStep);
    return _normalizeBearing(current + step);
  }

  LatLng _offsetForwardByMeters(LatLng point, double headingDeg, double meters) {
    if (meters <= 0) return point;
    final brng = _toRad(headingDeg);
    final lat1 = _toRad(point.latitude);
    final lng1 = _toRad(point.longitude);
    const earthR = 6371000.0;
    final angDist = meters / earthR;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(brng),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(brng) * math.sin(angDist) * math.cos(lat1),
          math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final brng = math.atan2(y, x) * 180.0 / math.pi;
    return _normalizeBearing(brng);
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Point du segment [a,b] le plus proche de [p], borné aux extrémités (approx. plan).
  LatLng _closestPointOnSegmentClamp(LatLng p, LatLng a, LatLng b) {
    final ay = a.latitude;
    final ax = a.longitude;
    final by = b.latitude;
    final bx = b.longitude;
    final py = p.latitude;
    final px = p.longitude;
    final abx = bx - ax;
    final aby = by - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 < 1e-20) {
      return a;
    }
    var t = ((px - ax) * abx + (py - ay) * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    return LatLng(ay + t * aby, ax + t * abx);
  }

  double _alongRaySignedMeters(LatLng origin, double headingDeg, LatLng p) {
    final dist = VehicleTrackingMath.distanceMeters(origin, p);
    if (dist < 0.4) {
      return 0.0;
    }
    final bearingToP = _bearingBetween(origin, p);
    final delta = _signedAngleDeltaDeg(headingDeg, bearingToP);
    return dist * math.cos(delta * math.pi / 180.0);
  }

  /// Limite l’extrapolation « tout droit » au-delà du dernier fix (temps × vitesse × slack).
  LatLng _clampAlongLastHeadingRay(LatLng logical, DateTime ts) {
    final origin = _lastRawSsePosition;
    final heading = _lastGpsHeading;
    final lastSse = _state.lastSseAt;
    if (origin == null || heading == null || lastSse == null) {
      return logical;
    }
    final elapsedSec = math.max(0.001, ts.difference(lastSse).inMilliseconds / 1000.0);
    var maxAlong = math.max(
      config.extrapolationAlongRayMarginMeters,
      _targetSpeedMps * elapsedSec * config.extrapolationAlongRaySlack,
    );
    maxAlong = math.min(maxAlong, config.extrapolationMaxAlongMeters);
    if (_lastSseChordMeters > 2.0) {
      maxAlong = math.min(
        maxAlong,
        _lastSseChordMeters * config.extrapolationChordSlack,
      );
    }
    final along = _alongRaySignedMeters(origin, heading, logical);
    if (along > maxAlong) {
      return _offsetForwardByMeters(origin, heading, maxAlong);
    }
    return logical;
  }

  double _elapsedSecForSse(Duration d) => (d.inMilliseconds / 1000).clamp(0.2, 20.0);
  double _elapsedSecForTick(Duration d) => (d.inMilliseconds / 1000).clamp(0.016, 0.25);
  double _toRad(double deg) => deg * math.pi / 180.0;
  double _normalizeBearing(double v) => (v % 360 + 360) % 360;
}
