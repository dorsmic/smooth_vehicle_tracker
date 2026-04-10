# Changelog

## 0.2.0

- Added `VehicleTrackingTicker` to centralize the dead-reckoning timer loop in the package.
- Improved tracking behavior for sparse updates:
  - rotate-then-move marker phase,
  - startup/pre-rotation/post-rotation blend phases,
  - tighter extrapolation clamps to reduce overshoot near turns,
  - better visual repaint gating for smoother marker updates.
- Expanded `VehicleTrackingConfig` with tuning knobs for rotation, startup blending, and extrapolation constraints.
- Exported ticker API from `smooth_vehicle_tracker.dart`.

## 0.1.0+2

- README orienté utilisateurs : prérequis Flutter/Google Maps, intégration (SSE, `tick`, polyligne), tableau de configuration `VehicleTrackingConfig`. Suppression des instructions réservées aux mainteneurs (publication Git/pub).

## 0.1.0+1

- Métadonnées pub.dev / README (dépôt GitHub, instructions d’installation).

## 0.1.0

- Initial release on pub.dev.
- `VehicleTrackingEngine` with dead reckoning, polyline snapping, heading smoothing, and soft SSE correction helpers.
- `VehicleTrackingConfig`, `VehicleTrackingState`, and `VehicleTrackingMath`.
