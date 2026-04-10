import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'vehicle_tracking_engine.dart';
import 'vehicle_tracking_models.dart';

typedef VehicleTrackingTickCallback = void Function(
  VehicleTrackingState state,
  DateTime now,
);

/// Orchestrateur léger du `tick()` moteur (timer périodique).
///
/// Permet de mutualiser la boucle de dead reckoning dans le package, sans
/// dépendre de Flutter widgets (`setState`, caméra, etc.).
class VehicleTrackingTicker {
  final VehicleTrackingEngine engine;
  final Duration interval;

  Timer? _timer;
  List<LatLng>? Function()? _polylineProvider;
  VehicleTrackingTickCallback? _onTick;

  VehicleTrackingTicker({
    required this.engine,
    this.interval = const Duration(milliseconds: 60),
  });

  bool get isRunning => _timer != null;

  bool get shouldRepaintMarker => engine.shouldRepaintMarker;

  VehicleTrackingState get state => engine.state;

  void onSsePosition(
    LatLng newPos, {
    DateTime? now,
    List<LatLng>? polyline,
  }) {
    engine.onSsePosition(newPos, now: now, polyline: polyline);
  }

  void start({
    VehicleTrackingTickCallback? onTick,
    List<LatLng>? Function()? polylineProvider,
  }) {
    _onTick = onTick ?? _onTick;
    _polylineProvider = polylineProvider ?? _polylineProvider;
    stop();
    _timer = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      final tracked = engine.tick(
        now: now,
        polyline: _polylineProvider?.call(),
      );
      _onTick?.call(tracked, now);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _onTick = null;
    _polylineProvider = null;
  }
}

