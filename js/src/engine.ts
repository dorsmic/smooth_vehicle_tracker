import type { VehicleTrackingConfig } from "./config.js";
import { mergeVehicleTrackingConfig } from "./config.js";
import * as VehicleTrackingMath from "./math.js";
import {
  copyVehicleTrackingState,
  initialVehicleTrackingState,
  type VehicleTrackingState,
} from "./models.js";
import type { LatLng } from "./types.js";

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180.0;
}

function normalizeBearing(v: number): number {
  return ((v % 360) + 360) % 360;
}

interface SegmentCandidate {
  point: LatLng;
  segmentIndex: number;
  distanceMeters: number;
  segmentHeading: number;
  score: number;
}

interface SnapResult {
  point: LatLng;
  segmentIndex: number;
  canSnap: boolean;
  isIntersectionMode: boolean;
}

interface PolylineMoveResult {
  position: LatLng;
  segmentIndex: number;
}

export class VehicleTrackingEngine {
  readonly config: VehicleTrackingConfig;
  private _state: VehicleTrackingState;
  private _lastTickAt: Date | null = null;
  private _lastRawSsePosition: LatLng | null = null;
  private _correctionTarget: LatLng | null = null;
  private _correctionWeight = 0.0;
  private _targetSpeedMps = 0.0;
  private _segmentChangeBoostFrames = 0;

  constructor(options: { config?: Partial<VehicleTrackingConfig>; initialPosition?: LatLng | null } = {}) {
    this.config = mergeVehicleTrackingConfig(options.config);
    this._state = initialVehicleTrackingState(options.initialPosition ?? undefined);
  }

  get state(): VehicleTrackingState {
    return this._state;
  }

  setInitialPosition(position: LatLng | null): void {
    this._state = copyVehicleTrackingState(this._state, {
      trackPosition: position,
      renderPosition:
        position === null
          ? null
          : this._offsetForwardByMeters(
              position,
              this._state.bearing,
              this.config.forwardPlacementMeters,
            ),
    });
    this._lastRawSsePosition = position;
  }

  onSsePosition(newPos: LatLng, options?: { now?: Date; polyline?: LatLng[] | null }): void {
    const ts = options?.now ?? new Date();
    const polyline = options?.polyline ?? undefined;
    const prevRaw = this._lastRawSsePosition;
    if (prevRaw === null) {
      this._lastRawSsePosition = newPos;
      this._state = copyVehicleTrackingState(this._state, {
        trackPosition: newPos,
        renderPosition: this._offsetForwardByMeters(
          newPos,
          this._state.bearing,
          this.config.forwardPlacementMeters,
        ),
        lastSseAt: ts,
      });
      return;
    }

    const movedMeters = VehicleTrackingMath.distanceMeters(prevRaw, newPos);
    const elapsedMs =
      this._state.lastSseAt === null ? 1000 : ts.getTime() - this._state.lastSseAt.getTime();

    if (movedMeters < this.config.minMoveMeters) {
      this._targetSpeedMps = 0.0;
      this._lastRawSsePosition = newPos;
      this._state = copyVehicleTrackingState(this._state, { speedMps: 0.0, lastSseAt: ts });
      return;
    }

    if (elapsedMs <= this.config.fastJumpWindowMs && movedMeters > this.config.maxJumpMeters) {
      return;
    }

    const dtSec = this._elapsedSecForSse(elapsedMs);
    const speedMps = clamp(movedMeters / dtSec, 0.0, this.config.maxSpeedMps);
    this._targetSpeedMps =
      speedMps < this.config.stationarySpeedEpsilonMps
        ? 0.0
        : clamp(speedMps, this.config.minSpeedMps, this.config.maxSpeedMps);

    const rawHeading = this._bearingBetween(prevRaw, newPos);
    const snapped = this._snapAndSelectSegment(
      newPos,
      polyline ?? null,
      rawHeading,
      this._state.segmentIndex,
    );

    let nextTrack = newPos;
    let segmentIndex = this._state.segmentIndex;
    let isIntersectionMode = false;

    if (snapped !== null) {
      isIntersectionMode = snapped.isIntersectionMode;
      if (snapped.canSnap) {
        nextTrack = snapped.point;
        if (snapped.segmentIndex !== this._state.segmentIndex) {
          this._segmentChangeBoostFrames = 6;
        }
        segmentIndex = snapped.segmentIndex;
      }
    }

    this._correctionTarget = nextTrack;
    this._correctionWeight = 1.0;
    this._lastRawSsePosition = newPos;
    this._state = copyVehicleTrackingState(this._state, {
      segmentIndex,
      isIntersectionMode,
      lastSseAt: ts,
    });
  }

  tick(options?: { now?: Date; polyline?: LatLng[] | null }): VehicleTrackingState {
    const ts = options?.now ?? new Date();
    const polyline = options?.polyline ?? undefined;
    const track = this._state.trackPosition;
    if (track === null) return this._state;

    const lastTick = this._lastTickAt;
    const dtMs = lastTick === null ? 0 : ts.getTime() - lastTick.getTime();
    this._lastTickAt = ts;
    const dtSec = this._elapsedSecForTick(dtMs);

    const lastSse = this._state.lastSseAt;
    const hasFreshSpeed =
      lastSse !== null && ts.getTime() - lastSse.getTime() <= this.config.freshSseWindowMs;
    const desired = clamp(
      hasFreshSpeed ? this._targetSpeedMps : this._state.speedMps * this.config.speedDecayPerSec,
      0.0,
      this.config.maxSpeedMps,
    );
    let currentSpeed =
      this._state.speedMps + (desired - this._state.speedMps) * this.config.speedSmoothing;
    if (!hasFreshSpeed && currentSpeed < this.config.stationarySpeedEpsilonMps) {
      currentSpeed = 0.0;
    }

    const movedDist = currentSpeed * dtSec;
    const advanced = this._moveAlongPolyline(
      track,
      movedDist,
      polyline ?? null,
      this._state.segmentIndex,
    );
    let logical = advanced.position;
    let segmentIndex = advanced.segmentIndex;

    const cTarget = this._correctionTarget;
    if (cTarget !== null && this._correctionWeight > 0.001) {
      const err = VehicleTrackingMath.distanceMeters(logical, cTarget);
      const factor =
        err > this.config.aggressiveCorrectionDistance
          ? this.config.aggressiveCorrectionFactor
          : this.config.baseCorrectionFactor;
      logical = this._lerpLatLng(
        logical,
        cTarget,
        clamp(factor * this._correctionWeight, 0.0, 0.5),
      );
      this._correctionWeight *= this.config.correctionDecayPerTick;
      if (err <= this.config.correctionStopDistanceMeters || this._correctionWeight <= 0.01) {
        this._correctionTarget = null;
        this._correctionWeight = 0.0;
      }
    }

    const routeHeading = this._routeHeadingFrom(
      logical,
      currentSpeed,
      polyline ?? null,
      segmentIndex,
      this._state.isIntersectionMode,
    );
    let headingTarget = routeHeading ?? this._state.bearing;
    if (
      movedDist <= this.config.headingFreezeMoveMeters &&
      this._segmentChangeBoostFrames <= 0 &&
      this._correctionWeight < 0.05
    ) {
      headingTarget = this._state.bearing;
    }

    const maxTurnRate =
      this._segmentChangeBoostFrames > 0 || this._state.isIntersectionMode
        ? this.config.maxTurnRateTickOnSegmentChangeDegPerSec
        : this.config.maxTurnRateTickDegPerSec;
    const bearing = this._smoothBearingLimited(
      this._state.bearing,
      headingTarget,
      this._adaptiveHeadingAlpha(currentSpeed),
      dtSec,
      maxTurnRate,
      this.config.bearingDeadbandDeg,
    );
    if (this._segmentChangeBoostFrames > 0) this._segmentChangeBoostFrames--;

    const render = this._offsetForwardByMeters(
      logical,
      bearing,
      this.config.forwardPlacementMeters,
    );
    this._state = copyVehicleTrackingState(this._state, {
      trackPosition: logical,
      renderPosition: render,
      bearing,
      speedMps: currentSpeed,
      segmentIndex,
    });
    return this._state;
  }

  private _snapAndSelectSegment(
    point: LatLng,
    polyline: LatLng[] | null,
    vehicleHeading: number,
    currentSegmentIndex: number,
  ): SnapResult | null {
    if (polyline === null || polyline.length < 2) return null;
    const maxIdx = polyline.length - 2;
    const lockedIdx = clamp(currentSegmentIndex, 0, maxIdx);
    const candidates: SegmentCandidate[] = [];

    for (let i = 0; i < polyline.length - 1; i++) {
      const s = polyline[i]!;
      const e = polyline[i + 1]!;
      const proj = this._projectPointOnSegment(point, s, e);
      const d = VehicleTrackingMath.distanceMeters(point, proj);
      if (d <= this.config.routeSnapReleaseDistanceMeters + 20) {
        const segHeading = this._bearingBetween(s, e);
        const angleDiff = VehicleTrackingMath.angleDeltaAbs(vehicleHeading, segHeading);
        const score = d + angleDiff * this.config.segmentAngleWeight;
        candidates.push({
          point: proj,
          segmentIndex: i,
          distanceMeters: d,
          segmentHeading: segHeading,
          score,
        });
      }
    }
    if (candidates.length === 0) return null;

    const isIntersectionMode =
      candidates.filter((c) => c.distanceMeters <= this.config.intersectionCandidateDistanceMeters)
        .length >= 2;
    candidates.sort((a, b) => a.score - b.score);
    let best = candidates[0]!;

    const allowedMin = clamp(lockedIdx - 1, 0, maxIdx);
    const allowedMax = clamp(lockedIdx + (isIntersectionMode ? 2 : 1), 0, maxIdx);
    if (best.segmentIndex < allowedMin || best.segmentIndex > allowedMax) {
      const filtered = candidates.filter(
        (c) => c.segmentIndex >= allowedMin && c.segmentIndex <= allowedMax,
      );
      if (filtered.length > 0) {
        filtered.sort((a, b) => a.score - b.score);
        best = filtered[0]!;
      }
    }

    const canSnap =
      best.distanceMeters <= this.config.routeSnapMaxDistanceMeters &&
      VehicleTrackingMath.angleDeltaAbs(vehicleHeading, best.segmentHeading) <=
        this.config.maxSnapHeadingDeltaDeg;

    return {
      point: best.point,
      segmentIndex: best.segmentIndex,
      canSnap,
      isIntersectionMode,
    };
  }

  private _moveAlongPolyline(
    current: LatLng,
    distanceMeters: number,
    polyline: LatLng[] | null,
    startSegmentIndex: number,
  ): PolylineMoveResult {
    if (polyline === null || polyline.length < 2 || distanceMeters <= 0) {
      return { position: current, segmentIndex: startSegmentIndex };
    }
    let idx = clamp(startSegmentIndex, 0, polyline.length - 2);
    let cursor = current;
    let remaining = distanceMeters;
    while (remaining > 0 && idx < polyline.length - 1) {
      const next = polyline[idx + 1]!;
      const seg = VehicleTrackingMath.distanceMeters(cursor, next);
      if (seg <= 0.01) {
        cursor = next;
        idx = clamp(idx + 1, 0, polyline.length - 2);
        continue;
      }
      if (seg >= remaining) {
        const ratio = clamp(remaining / seg, 0.0, 1.0);
        cursor = this._lerpLatLng(cursor, next, ratio);
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
    return { position: cursor, segmentIndex: idx };
  }

  private _routeHeadingFrom(
    from: LatLng,
    speedMps: number,
    polyline: LatLng[] | null,
    segmentIndex: number,
    isIntersectionMode: boolean,
  ): number | null {
    if (polyline === null || polyline.length < 2) return null;
    const lookAhead =
      clamp(
        speedMps * this.config.lookAheadSpeedFactor,
        this.config.lookAheadMinMeters,
        this.config.lookAheadMaxMeters,
      ) + (isIntersectionMode ? this.config.intersectionExtraLookAheadMeters : 0.0);
    let idx = clamp(segmentIndex, 0, polyline.length - 2);
    let cursor = from;
    let remain = lookAhead;
    while (remain > 0 && idx < polyline.length - 1) {
      const next = polyline[idx + 1]!;
      const seg = VehicleTrackingMath.distanceMeters(cursor, next);
      if (seg >= remain) {
        const t = clamp(remain / seg, 0.0, 1.0);
        return this._bearingBetween(from, this._lerpLatLng(cursor, next, t));
      }
      remain -= seg;
      cursor = next;
      idx++;
    }
    const fallback = clamp(idx + 1, 1, polyline.length - 1);
    return this._bearingBetween(from, polyline[fallback]!);
  }

  private _adaptiveHeadingAlpha(speedMps: number): number {
    if (speedMps < 2) return 0.12;
    if (speedMps < 8) return 0.18;
    if (speedMps < 18) return 0.24;
    return 0.28;
  }

  private _smoothBearingLimited(
    current: number,
    target: number,
    alpha: number,
    dtSec: number,
    maxTurnRateDegPerSec: number,
    deadbandDeg: number,
  ): number {
    const delta = ((((target - current) + 540) % 360) - 180) as number;
    if (Math.abs(delta) <= deadbandDeg) return current;
    const wanted = delta * alpha;
    const maxStep = clamp(maxTurnRateDegPerSec * dtSec, 0.6, 18.0);
    const step = clamp(wanted, -maxStep, maxStep);
    return normalizeBearing(current + step);
  }

  private _projectPointOnSegment(p: LatLng, a: LatLng, b: LatLng): LatLng {
    const lat0 = toRad(a.lat);
    const bx = toRad(b.lng - a.lng) * Math.cos(lat0);
    const by = toRad(b.lat - a.lat);
    const px = toRad(p.lng - a.lng) * Math.cos(lat0);
    const py = toRad(p.lat - a.lat);
    const den = bx * bx + by * by;
    if (den <= 1e-12) return a;
    const t = clamp((px * bx + py * by) / den, 0.0, 1.0);
    const qx = bx * t;
    const qy = by * t;
    return {
      lat: a.lat + (qy * 180.0) / Math.PI,
      lng: a.lng + (qx / Math.cos(lat0)) * (180.0 / Math.PI),
    };
  }

  private _offsetForwardByMeters(point: LatLng, headingDeg: number, meters: number): LatLng {
    if (meters <= 0) return point;
    const brng = toRad(headingDeg);
    const lat1 = toRad(point.lat);
    const lng1 = toRad(point.lng);
    const earthR = 6371000.0;
    const angDist = meters / earthR;
    const lat2 = Math.asin(
      Math.sin(lat1) * Math.cos(angDist) +
        Math.cos(lat1) * Math.sin(angDist) * Math.cos(brng),
    );
    const lng2 =
      lng1 +
      Math.atan2(
        Math.sin(brng) * Math.sin(angDist) * Math.cos(lat1),
        Math.cos(angDist) - Math.sin(lat1) * Math.sin(lat2),
      );
    return { lat: (lat2 * 180) / Math.PI, lng: (lng2 * 180) / Math.PI };
  }

  private _bearingBetween(a: LatLng, b: LatLng): number {
    const lat1 = toRad(a.lat);
    const lat2 = toRad(b.lat);
    const dLng = toRad(b.lng - a.lng);
    const y = Math.sin(dLng) * Math.cos(lat2);
    const x =
      Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
    const brng = (Math.atan2(y, x) * 180.0) / Math.PI;
    return normalizeBearing(brng);
  }

  private _lerpLatLng(a: LatLng, b: LatLng, t: number): LatLng {
    return {
      lat: a.lat + (b.lat - a.lat) * t,
      lng: a.lng + (b.lng - a.lng) * t,
    };
  }

  private _elapsedSecForSse(ms: number): number {
    return clamp(ms / 1000, 0.2, 20.0);
  }

  private _elapsedSecForTick(ms: number): number {
    return clamp(ms / 1000, 0.016, 0.25);
  }
}
