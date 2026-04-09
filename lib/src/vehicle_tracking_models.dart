import 'package:google_maps_flutter/google_maps_flutter.dart';

class VehicleTrackingState {
  final LatLng? trackPosition;
  final LatLng? renderPosition;
  final double bearing;
  final double speedMps;
  final int segmentIndex;
  final bool isIntersectionMode;
  final DateTime? lastSseAt;

  const VehicleTrackingState({
    required this.trackPosition,
    required this.renderPosition,
    required this.bearing,
    required this.speedMps,
    required this.segmentIndex,
    required this.isIntersectionMode,
    required this.lastSseAt,
  });

  factory VehicleTrackingState.initial([LatLng? initial]) {
    return VehicleTrackingState(
      trackPosition: initial,
      renderPosition: initial,
      bearing: 0.0,
      speedMps: 0.0,
      segmentIndex: 0,
      isIntersectionMode: false,
      lastSseAt: null,
    );
  }

  VehicleTrackingState copyWith({
    LatLng? trackPosition,
    LatLng? renderPosition,
    double? bearing,
    double? speedMps,
    int? segmentIndex,
    bool? isIntersectionMode,
    DateTime? lastSseAt,
  }) {
    return VehicleTrackingState(
      trackPosition: trackPosition ?? this.trackPosition,
      renderPosition: renderPosition ?? this.renderPosition,
      bearing: bearing ?? this.bearing,
      speedMps: speedMps ?? this.speedMps,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      isIntersectionMode: isIntersectionMode ?? this.isIntersectionMode,
      lastSseAt: lastSseAt ?? this.lastSseAt,
    );
  }
}
