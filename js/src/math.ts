import type { LatLng } from "./types.js";

const EARTH_R = 6371000.0;

function toRad(deg: number): number {
  return (deg * Math.PI) / 180.0;
}

export function angleDeltaAbs(a: number, b: number): number {
  const d = ((((b - a) + 540) % 360) - 180) as number;
  return Math.abs(d);
}

export function distanceMeters(a: LatLng, b: LatLng): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * EARTH_R * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}
