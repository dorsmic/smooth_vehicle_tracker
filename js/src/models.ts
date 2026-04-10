import type { LatLng } from "./types.js";

export interface VehicleTrackingState {
  trackPosition: LatLng | null;
  renderPosition: LatLng | null;
  bearing: number;
  speedMps: number;
  segmentIndex: number;
  isIntersectionMode: boolean;
  lastSseAt: Date | null;
}

export function initialVehicleTrackingState(initial?: LatLng | null): VehicleTrackingState {
  return {
    trackPosition: initial ?? null,
    renderPosition: initial ?? null,
    bearing: 0.0,
    speedMps: 0.0,
    segmentIndex: 0,
    isIntersectionMode: false,
    lastSseAt: null,
  };
}

export function copyVehicleTrackingState(
  s: VehicleTrackingState,
  patch: Partial<VehicleTrackingState>,
): VehicleTrackingState {
  return {
    trackPosition: patch.trackPosition ?? s.trackPosition,
    renderPosition: patch.renderPosition ?? s.renderPosition,
    bearing: patch.bearing ?? s.bearing,
    speedMps: patch.speedMps ?? s.speedMps,
    segmentIndex: patch.segmentIndex ?? s.segmentIndex,
    isIntersectionMode: patch.isIntersectionMode ?? s.isIntersectionMode,
    lastSseAt: patch.lastSseAt ?? s.lastSseAt,
  };
}
