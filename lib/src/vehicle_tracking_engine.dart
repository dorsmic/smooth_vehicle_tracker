import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'vehicle_tracking_config.dart';
import 'vehicle_tracking_math.dart';
import 'vehicle_tracking_models.dart';

class VehicleTrackingEngine {
  final VehicleTrackingConfig config;

  VehicleTrackingState _state;
  DateTime? _lastTickAt;
  LatLng? _lastRawSsePosition;
  LatLng? _correctionTarget;
  double _correctionWeight = 0.0;
  double _targetSpeedMps = 0.0;
  int _segmentChangeBoostFrames = 0;

  VehicleTrackingEngine({
    required this.config,
    LatLng? initialPosition,
  }) : _state = VehicleTrackingState.initial(initialPosition);

  VehicleTrackingState get state => _state;

  void setInitialPosition(LatLng? position) {
    _state = _state.copyWith(
      trackPosition: position,
      renderPosition: position == null ? null : _offsetForwardByMeters(position, _state.bearing, config.forwardPlacementMeters),
    );
    _lastRawSsePosition = position;
  }

  void onSsePosition(LatLng newPos, {DateTime? now, List<LatLng>? polyline}) {
    final ts = now ?? DateTime.now();
    final prevRaw = _lastRawSsePosition;
    if (prevRaw == null) {
      _lastRawSsePosition = newPos;
      _state = _state.copyWith(
        trackPosition: newPos,
        renderPosition: _offsetForwardByMeters(newPos, _state.bearing, config.forwardPlacementMeters),
        lastSseAt: ts,
      );
      return;
    }

    final movedMeters = VehicleTrackingMath.distanceMeters(prevRaw, newPos);
    final elapsed = _state.lastSseAt == null ? const Duration(seconds: 1) : ts.difference(_state.lastSseAt!);

    if (movedMeters < config.minMoveMeters) {
      _targetSpeedMps = 0.0;
      _lastRawSsePosition = newPos;
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
    final snapped = _snapAndSelectSegment(
      point: newPos,
      polyline: polyline,
      vehicleHeading: rawHeading,
      currentSegmentIndex: _state.segmentIndex,
    );

    var nextTrack = newPos;
    var segmentIndex = _state.segmentIndex;
    var isIntersectionMode = false;

    if (snapped != null) {
      isIntersectionMode = snapped.isIntersectionMode;
      if (snapped.canSnap) {
        nextTrack = snapped.point;
        if (snapped.segmentIndex != _state.segmentIndex) {
          _segmentChangeBoostFrames = 6;
        }
        segmentIndex = snapped.segmentIndex;
      }
    }

    _correctionTarget = nextTrack;
    _correctionWeight = 1.0;
    _lastRawSsePosition = newPos;
    _state = _state.copyWith(
      segmentIndex: segmentIndex,
      isIntersectionMode: isIntersectionMode,
      lastSseAt: ts,
    );
  }

  VehicleTrackingState tick({DateTime? now, List<LatLng>? polyline}) {
    final ts = now ?? DateTime.now();
    final track = _state.trackPosition;
    if (track == null) return _state;

    final dt = ts.difference(_lastTickAt ?? ts);
    _lastTickAt = ts;
    final dtSec = _elapsedSecForTick(dt);

    final hasFreshSpeed = _state.lastSseAt != null && ts.difference(_state.lastSseAt!) <= config.freshSseWindow;
    final desired = (hasFreshSpeed ? _targetSpeedMps : _state.speedMps * config.speedDecayPerSec).clamp(0.0, config.maxSpeedMps);
    var currentSpeed = _state.speedMps + (desired - _state.speedMps) * config.speedSmoothing;
    if (!hasFreshSpeed && currentSpeed < config.stationarySpeedEpsilonMps) {
      currentSpeed = 0.0;
    }

    final movedDist = currentSpeed * dtSec;
    final advanced = _moveAlongPolyline(
      current: track,
      distanceMeters: movedDist,
      polyline: polyline,
      startSegmentIndex: _state.segmentIndex,
    );
    var logical = advanced.position;
    var segmentIndex = advanced.segmentIndex;

    final cTarget = _correctionTarget;
    if (cTarget != null && _correctionWeight > 0.001) {
      final err = VehicleTrackingMath.distanceMeters(logical, cTarget);
      final factor = err > config.aggressiveCorrectionDistance
          ? config.aggressiveCorrectionFactor
          : config.baseCorrectionFactor;
      logical = _lerpLatLng(logical, cTarget, (factor * _correctionWeight).clamp(0.0, 0.5));
      _correctionWeight *= config.correctionDecayPerTick;
      if (err <= config.correctionStopDistanceMeters || _correctionWeight <= 0.01) {
        _correctionTarget = null;
        _correctionWeight = 0.0;
      }
    }

    final routeHeading = _routeHeadingFrom(
      from: logical,
      speedMps: currentSpeed,
      polyline: polyline,
      segmentIndex: segmentIndex,
      isIntersectionMode: _state.isIntersectionMode,
    );
    var headingTarget = routeHeading ?? _state.bearing;
    if (movedDist <= config.headingFreezeMoveMeters &&
        _segmentChangeBoostFrames <= 0 &&
        _correctionWeight < 0.05) {
      headingTarget = _state.bearing;
    }

    final maxTurnRate = (_segmentChangeBoostFrames > 0 || _state.isIntersectionMode)
        ? config.maxTurnRateTickOnSegmentChangeDegPerSec
        : config.maxTurnRateTickDegPerSec;
    final bearing = _smoothBearingLimited(
      current: _state.bearing,
      target: headingTarget,
      alpha: _adaptiveHeadingAlpha(currentSpeed),
      dtSec: dtSec,
      maxTurnRateDegPerSec: maxTurnRate,
      deadbandDeg: config.bearingDeadbandDeg,
    );
    if (_segmentChangeBoostFrames > 0) _segmentChangeBoostFrames--;

    final render = _offsetForwardByMeters(logical, bearing, config.forwardPlacementMeters);
    _state = _state.copyWith(
      trackPosition: logical,
      renderPosition: render,
      bearing: bearing,
      speedMps: currentSpeed,
      segmentIndex: segmentIndex,
    );
    return _state;
  }

  _SnapResult? _snapAndSelectSegment({
    required LatLng point,
    required List<LatLng>? polyline,
    required double vehicleHeading,
    required int currentSegmentIndex,
  }) {
    if (polyline == null || polyline.length < 2) return null;
    final maxIdx = polyline.length - 2;
    final lockedIdx = currentSegmentIndex.clamp(0, maxIdx);
    final candidates = <_SegmentCandidate>[];

    for (int i = 0; i < polyline.length - 1; i++) {
      final s = polyline[i];
      final e = polyline[i + 1];
      final proj = _projectPointOnSegment(point, s, e);
      final d = VehicleTrackingMath.distanceMeters(point, proj);
      if (d <= config.routeSnapReleaseDistanceMeters + 20) {
        final segHeading = _bearingBetween(s, e);
        final angleDiff = VehicleTrackingMath.angleDeltaAbs(vehicleHeading, segHeading);
        final score = d + angleDiff * config.segmentAngleWeight;
        candidates.add(_SegmentCandidate(
          point: proj,
          segmentIndex: i,
          distanceMeters: d,
          segmentHeading: segHeading,
          score: score,
        ));
      }
    }
    if (candidates.isEmpty) return null;

    final isIntersectionMode = candidates.where((c) => c.distanceMeters <= config.intersectionCandidateDistanceMeters).length >= 2;
    candidates.sort((a, b) => a.score.compareTo(b.score));
    var best = candidates.first;

    final allowedMin = (lockedIdx - 1).clamp(0, maxIdx);
    final allowedMax = (lockedIdx + (isIntersectionMode ? 2 : 1)).clamp(0, maxIdx);
    if (best.segmentIndex < allowedMin || best.segmentIndex > allowedMax) {
      final filtered = candidates.where((c) => c.segmentIndex >= allowedMin && c.segmentIndex <= allowedMax).toList();
      if (filtered.isNotEmpty) {
        filtered.sort((a, b) => a.score.compareTo(b.score));
        best = filtered.first;
      }
    }

    final canSnap = best.distanceMeters <= config.routeSnapMaxDistanceMeters &&
        VehicleTrackingMath.angleDeltaAbs(vehicleHeading, best.segmentHeading) <= config.maxSnapHeadingDeltaDeg;

    return _SnapResult(
      point: best.point,
      segmentIndex: best.segmentIndex,
      canSnap: canSnap,
      isIntersectionMode: isIntersectionMode,
    );
  }

  _PolylineMoveResult _moveAlongPolyline({
    required LatLng current,
    required double distanceMeters,
    required List<LatLng>? polyline,
    required int startSegmentIndex,
  }) {
    if (polyline == null || polyline.length < 2 || distanceMeters <= 0) {
      return _PolylineMoveResult(position: current, segmentIndex: startSegmentIndex);
    }
    int idx = startSegmentIndex.clamp(0, polyline.length - 2);
    LatLng cursor = current;
    double remaining = distanceMeters;
    while (remaining > 0 && idx < polyline.length - 1) {
      final next = polyline[idx + 1];
      final seg = VehicleTrackingMath.distanceMeters(cursor, next);
      if (seg <= 0.01) {
        cursor = next;
        idx = (idx + 1).clamp(0, polyline.length - 2);
        continue;
      }
      if (seg >= remaining) {
        final ratio = (remaining / seg).clamp(0.0, 1.0);
        cursor = _lerpLatLng(cursor, next, ratio);
        break;
      }
      remaining -= seg;
      cursor = next;
      if (idx < polyline.length - 2) {
        idx++;
      } else {
        break;
      }
    }
    return _PolylineMoveResult(position: cursor, segmentIndex: idx);
  }

  double? _routeHeadingFrom({
    required LatLng from,
    required double speedMps,
    required List<LatLng>? polyline,
    required int segmentIndex,
    required bool isIntersectionMode,
  }) {
    if (polyline == null || polyline.length < 2) return null;
    final lookAhead = (speedMps * config.lookAheadSpeedFactor).clamp(config.lookAheadMinMeters, config.lookAheadMaxMeters) +
        (isIntersectionMode ? config.intersectionExtraLookAheadMeters : 0.0);
    int idx = segmentIndex.clamp(0, polyline.length - 2);
    LatLng cursor = from;
    double remain = lookAhead;
    while (remain > 0 && idx < polyline.length - 1) {
      final next = polyline[idx + 1];
      final seg = VehicleTrackingMath.distanceMeters(cursor, next);
      if (seg >= remain) {
        final t = (remain / seg).clamp(0.0, 1.0);
        return _bearingBetween(from, _lerpLatLng(cursor, next, t));
      }
      remain -= seg;
      cursor = next;
      idx++;
    }
    final fallback = (idx + 1).clamp(1, polyline.length - 1);
    return _bearingBetween(from, polyline[fallback]);
  }

  double _adaptiveHeadingAlpha(double speedMps) {
    if (speedMps < 2) return 0.12;
    if (speedMps < 8) return 0.18;
    if (speedMps < 18) return 0.24;
    return 0.28;
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
    final maxStep = (maxTurnRateDegPerSec * dtSec).clamp(0.6, 18.0);
    final step = wanted.clamp(-maxStep, maxStep);
    return _normalizeBearing(current + step);
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final lat0 = _toRad(a.latitude);
    const ax = 0.0;
    const ay = 0.0;
    final bx = _toRad(b.longitude - a.longitude) * math.cos(lat0);
    final by = _toRad(b.latitude - a.latitude);
    final px = _toRad(p.longitude - a.longitude) * math.cos(lat0);
    final py = _toRad(p.latitude - a.latitude);
    final den = bx * bx + by * by;
    if (den <= 1e-12) return a;
    final t = ((px * bx + py * by) / den).clamp(0.0, 1.0);
    final qx = ax + (bx - ax) * t;
    final qy = ay + (by - ay) * t;
    return LatLng(
      a.latitude + (qy * 180.0 / math.pi),
      a.longitude + (qx / math.cos(lat0)) * 180.0 / math.pi,
    );
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

  double _elapsedSecForSse(Duration d) => (d.inMilliseconds / 1000).clamp(0.2, 20.0);
  double _elapsedSecForTick(Duration d) => (d.inMilliseconds / 1000).clamp(0.016, 0.25);
  double _toRad(double deg) => deg * math.pi / 180.0;
  double _normalizeBearing(double v) => (v % 360 + 360) % 360;
}

class _SegmentCandidate {
  final LatLng point;
  final int segmentIndex;
  final double distanceMeters;
  final double segmentHeading;
  final double score;

  const _SegmentCandidate({
    required this.point,
    required this.segmentIndex,
    required this.distanceMeters,
    required this.segmentHeading,
    required this.score,
  });
}

class _SnapResult {
  final LatLng point;
  final int segmentIndex;
  final bool canSnap;
  final bool isIntersectionMode;

  const _SnapResult({
    required this.point,
    required this.segmentIndex,
    required this.canSnap,
    required this.isIntersectionMode,
  });
}

class _PolylineMoveResult {
  final LatLng position;
  final int segmentIndex;

  const _PolylineMoveResult({
    required this.position,
    required this.segmentIndex,
  });
}
