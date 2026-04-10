# smooth_vehicle_tracker

Vehicle tracking on Flutter maps (Google Maps): interpolation between sparse server positions (SSE), snapping to a route polyline, smoothed bearing, and gradual correction without marker “teleporting”.

## Installation

```yaml
dependencies:
  smooth_vehicle_tracker: ^0.2.0
```

From Git:

```yaml
dependencies:
  smooth_vehicle_tracker:
    git:
      url: https://github.com/dorsmic/smooth_vehicle_tracker.git
      ref: main
```

## Requirements (Flutter app)

- **Flutter** and **Dart** within the ranges declared in this package’s `pubspec` (`environment`).
- **Google Maps**: this package depends on `google_maps_flutter` (`LatLng`, polylines). Configure your app like any standard map integration: Android/iOS API keys, permissions, etc. — see the [plugin documentation](https://pub.dev/packages/google_maps_flutter).

No extra keys or config files are required **specifically** for `smooth_vehicle_tracker`: only the map and positions (`LatLng`) matter.

## Minimal integration

1. **Create** a `VehicleTrackingEngine` with a `VehicleTrackingConfig` (or defaults) and, if available, an **initial** on-route position.
2. **On each position from the backend** (SSE, WebSocket, polling, etc.), call  
   `engine.onSsePosition(newPosition, polyline: routePoints)`  
   using the same point list as the polyline drawn on the map (identical order). Omit `polyline` if you do not use route snapping.
3. **On a steady schedule** (timer, `Ticker`, animation loop), call  
   `engine.tick(polyline: routePoints)`  
   passing the same polyline when used. **Recommended**: match the period to `config.tickInterval` (default **60 ms**), e.g. `Timer.periodic(config.tickInterval, (_) { ... })`, so speed and heading tuning stay consistent.
4. **Read state**: after `tick`, use `renderPosition` and `bearing` for the **marker** (rotated icon), and `trackPosition` for the **camera** or business logic if you want the on-route point without the small forward render offset.

## Configuration (`VehicleTrackingConfig`)

All fields have **defaults** suited to urban tracking. Override them in the constructor:

```dart
const config = VehicleTrackingConfig(
  tickInterval: Duration(milliseconds: 50),
  routeSnapMaxDistanceMeters: 35.0,
);
```

### Tick cadence and server updates

| Parameter | Summary |
|-----------|---------|
| `tickInterval` | Target period for your `tick` calls (for your timer; the engine uses the actual `dt` between ticks). |
| `freshSseWindow` | How long speed inferred from the last SSE stays “fresh” for dead reckoning. |
| `minMoveMeters` | Minimum move between two SSE updates to avoid noise (otherwise speed goes to 0). |
| `maxJumpMeters` / `fastJumpWindow` | Drop impossible jumps within a short time window (anti-spike). |

### Speed and inertia

| Parameter | Summary |
|-----------|---------|
| `minSpeedMps` / `maxSpeedMps` | Estimated speed bounds (m/s). |
| `speedSmoothing` | Smooth displayed speed toward the target. |
| `speedDecayPerSec` | Speed decay when there is no recent SSE. |
| `stationarySpeedEpsilonMps` | Below this, the vehicle is treated as stopped. |

### Snapping to the route (polyline)

| Parameter | Summary |
|-----------|---------|
| `routeSnapMaxDistanceMeters` | Max distance to project position onto the route. |
| `routeSnapReleaseDistanceMeters` | Beyond this, snapping is released. |
| `segmentAngleWeight`, `maxSnapHeadingDeltaDeg`, `routeHeadingBlend` | Segment choice and heading / route blending. |
| `lookAheadMinMeters`, `lookAheadMaxMeters`, `lookAheadSpeedFactor` | Look-ahead along the route vs speed. |
| `intersectionExtraLookAheadMeters`, `intersectionCandidateDistanceMeters` | Behavior near intersections. |

### Correction after an SSE update

| Parameter | Summary |
|-----------|---------|
| `baseCorrectionFactor` / `aggressiveCorrectionFactor` / `aggressiveCorrectionDistance` | How strongly to correct toward the target vs error. |
| `correctionDecayPerTick` | Correction damping over time. |
| `correctionStopDistanceMeters` | Stop correcting when close enough. |

### Heading (bearing)

| Parameter | Summary |
|-----------|---------|
| `maxTurnRateTickDegPerSec`, `maxTurnRateSseDegPerSec` | Heading rotation limits between ticks / on SSE. |
| `maxTurnRateTickOnSegmentChangeDegPerSec`, `maxTurnRateSseOnSegmentChangeDegPerSec` | Stricter limits shortly after a segment change. |
| `bearingDeadbandDeg` | Deadband to reduce heading jitter. |
| `headingFreezeMoveMeters` | Partially freeze heading when movement is very small. |

### Marker rendering

| Parameter | Summary |
|-----------|---------|
| `forwardPlacementMeters` | Nudges **displayed** position forward along bearing (visual icon offset). |
| `vehicleAnchor` | Normalized `Offset` anchor for a vehicle bitmap (default slightly forward of center). |

Exact names and full defaults are in `lib/src/vehicle_tracking_config.dart`.

## Example flow

```dart
final engine = VehicleTrackingEngine(
  config: const VehicleTrackingConfig(),
  initialPosition: firstKnownLatLng,
);

// When a server position arrives:
engine.onSsePosition(serverLatLng, polyline: routeLatLngs);

// On a timer aligned with config.tickInterval:
final next = engine.tick(polyline: routeLatLngs);
final markerPosition = next.renderPosition;
final markerBearing = next.bearing;
// next.trackPosition → camera / logic along the path
```

## Repository and package

- Repository: [github.com/dorsmic/smooth_vehicle_tracker](https://github.com/dorsmic/smooth_vehicle_tracker)  
- Package: [pub.dev/packages/smooth_vehicle_tracker](https://pub.dev/packages/smooth_vehicle_tracker)

## License

MIT — see [LICENSE](LICENSE).
