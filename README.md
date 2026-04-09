# smooth_vehicle_tracker

Dead reckoning and polyline-based vehicle tracking for Flutter maps (e.g. Google Maps): smooth motion between sparse position updates (SSE), route snapping, predictive heading, and soft correction without teleporting the marker.

## Install

```yaml
dependencies:
  smooth_vehicle_tracker: ^0.1.0+1
```

Or from Git:

```yaml
dependencies:
  smooth_vehicle_tracker:
    git:
      url: https://github.com/dorsmic/smooth_vehicle_tracker.git
      ref: main
```

## Usage

```dart
final engine = VehicleTrackingEngine(
  config: const VehicleTrackingConfig(),
  initialPosition: initialLatLng,
);

// On each server position (SSE):
engine.onSsePosition(newSseLatLng, polyline: routePolyline);

// On a short timer (e.g. same as VehicleTrackingConfig.tickInterval conceptually):
final next = engine.tick(polyline: routePolyline);

final markerPos = next.renderPosition;
final markerBearing = next.bearing;
```

Use `next.trackPosition` for camera / logic and `next.renderPosition` for the marker (includes a small forward offset when configured).

## Repository

[https://github.com/dorsmic/smooth_vehicle_tracker](https://github.com/dorsmic/smooth_vehicle_tracker)

Remote Git en **HTTPS** : `https://github.com/dorsmic/smooth_vehicle_tracker.git`

### Première publication (dépôt vide sur GitHub)

Le dépôt peut rester vide au début ([état actuel possible](https://github.com/dorsmic/smooth_vehicle_tracker)). Il faut un premier push pour que `flutter pub get` avec dépendance `git` fonctionne.

Sur ta machine (authentification GitHub : navigateur, **Personal Access Token**, ou **GitHub CLI** `gh auth login`) :

```bash
cd packages/smooth_vehicle_tracker
./tool/force_push_github.sh
```

Le script utilise **`git remote add origin https://github.com/dorsmic/smooth_vehicle_tracker.git`** puis **`git push -u origin main --force`**.

### Équivalent des instructions GitHub (HTTPS)

```bash
git init
git branch -M main
git remote add origin https://github.com/dorsmic/smooth_vehicle_tracker.git
git add -A
git commit -m "Release smooth_vehicle_tracker"
git push -u origin main --force
```

Si tu avais seulement le README créé depuis le site GitHub, le `--force` remplace l’historique par le contenu du package (voulu).

## License

MIT (see [LICENSE](LICENSE)).
