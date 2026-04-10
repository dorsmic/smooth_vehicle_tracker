# smooth-vehicle-tracker (JavaScript / TypeScript)

Port of the Dart [`smooth_vehicle_tracker`](../) engine for **web** maps. Same dead reckoning, polyline snapping, and smoothed bearing. Positions are plain **`{ lat, lng }`** objects (same shape as [`google.maps.LatLngLiteral`](https://developers.google.com/maps/documentation/javascript/reference/coordinates#LatLngLiteral)).

**Package:** [npmjs.com/package/smooth-vehicle-tracker](https://www.npmjs.com/package/smooth-vehicle-tracker)

## Install

```bash
npm install smooth-vehicle-tracker
```

## Build (from source / contributors)

```bash
npm install
npm run build
```

Output: ESM + `.d.ts` in `dist/`.

## Usage (Google Maps JavaScript API)

```ts
import {
  VehicleTrackingEngine,
  defaultVehicleTrackingConfig,
} from "smooth-vehicle-tracker";

const engine = new VehicleTrackingEngine({
  config: defaultVehicleTrackingConfig,
  initialPosition: { lat: 48.8566, lng: 2.3522 },
});

// When your backend sends a position (SSE, WebSocket, etc.):
engine.onSsePosition(
  { lat: newLat, lng: newLng },
  { polyline: routePoints },
);

// On an interval matching config.tickIntervalMs (default 60 ms):
const { renderPosition, bearing } = engine.tick({ polyline: routePoints });

if (renderPosition) {
  marker.setPosition(renderPosition);
  marker.setIcon({
    path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
    scale: 4,
    rotation: bearing,
    anchor: new google.maps.Point(
      engine.config.vehicleAnchor.x * iconWidth,
      engine.config.vehicleAnchor.y * iconHeight,
    ),
  });
}
```

Use **`renderPosition`** for the marker and **`trackPosition`** for camera / logic (see Flutter package README for the same distinction).

### Local path / monorepo

```json
"dependencies": {
  "smooth-vehicle-tracker": "file:../smooth_vehicle_tracker/js"
}
```

After `npm run build` in `js/`, install from your app.

## Configuration

Durations are in **milliseconds** (`tickIntervalMs`, `fastJumpWindowMs`, `freshSseWindowMs`) instead of Dart `Duration`. Override any field:

```ts
import { mergeVehicleTrackingConfig, VehicleTrackingEngine } from "smooth-vehicle-tracker";

const engine = new VehicleTrackingEngine({
  config: mergeVehicleTrackingConfig({ tickIntervalMs: 50 }),
});
```

## License

MIT (same as the repository root).
