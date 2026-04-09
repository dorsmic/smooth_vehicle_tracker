import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class VehicleTrackingMath {
  const VehicleTrackingMath._();

  static double angleDeltaAbs(double a, double b) {
    final d = (((b - a) + 540) % 360) - 180;
    return d.abs();
  }

  static double distanceMeters(LatLng a, LatLng b) {
    const earthR = 6371000.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * earthR * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
}
