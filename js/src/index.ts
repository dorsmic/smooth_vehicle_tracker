export type { LatLng } from "./types.js";
export type { VehicleAnchor, VehicleTrackingConfig } from "./config.js";
export {
  defaultVehicleTrackingConfig,
  mergeVehicleTrackingConfig,
} from "./config.js";
export type { VehicleTrackingState } from "./models.js";
export { copyVehicleTrackingState, initialVehicleTrackingState } from "./models.js";
export * as VehicleTrackingMath from "./math.js";
export { VehicleTrackingEngine } from "./engine.js";
export type { VehicleTrackingTickCallback } from "./ticker.js";
export { VehicleTrackingTicker } from "./ticker.js";
