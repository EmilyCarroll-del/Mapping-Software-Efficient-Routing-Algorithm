import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vector_math/vector_math.dart';
// import 'package:geolocator/geolocator.dart'; // Removed to avoid potential platform channel overhead in loops

import '../models/route_optimization.dart';
import '../models/delivery_address.dart';

class TurnByTurnService {
  static const double _kTurnThreshold = 25.0;
  static const double _kMinDistanceBetweenTurns = 50.0;

  static Future<List<RouteStep>> generateSteps(List<LatLng> routePoints) async {
    if (routePoints.length < 3) {
      return [];
    }

    final List<RouteStep> steps = [];
    double distanceSinceLastTurn = 0.0;

    for (int i = 1; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i - 1];
      final p2 = routePoints[i];
      final p3 = routePoints[i + 1];

      // Use local Haversine calculation instead of Geolocator to ensure pure Dart performance
      distanceSinceLastTurn += _calculateDistance(
        p1.latitude, p1.longitude,
        p2.latitude, p2.longitude,
      );

      final turnAngle = _calculateTurnAngle(p1, p2, p3);

      if (turnAngle.abs() > _kTurnThreshold && distanceSinceLastTurn > _kMinDistanceBetweenTurns) {
        String turnDirection = turnAngle > 0 ? "Turn right" : "Turn left";
        
        final String instruction = turnDirection;

        if (steps.isNotEmpty && steps.last.instructions == instruction) {
            continue;
        }

        // --- FIX: Correctly using the named constructor or default ---
        steps.add(RouteStep(
          sequenceNumber: steps.length + 1,
          address: DeliveryAddress.fromCoordinates(
            latitude: p2.latitude,
            longitude: p2.longitude,
          ),
          instructions: instruction,
          distanceFromPrevious: distanceSinceLastTurn / 1000, // Convert meters to km
        ));

        distanceSinceLastTurn = 0.0;
      }
    }
    
    return steps;
  }


  // --- Core Mathematical Functions ---

  /// Calculates the distance between two points in meters using the Haversine formula.
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // Earth radius in meters
    final double phi1 = radians(lat1);
    final double phi2 = radians(lat2);
    final double deltaPhi = radians(lat2 - lat1);
    final double deltaLambda = radians(lon2 - lon1);

    final double a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) * math.cos(phi2) *
            math.sin(deltaLambda / 2) * math.sin(deltaLambda / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  static double _calculateBearing(LatLng point1, LatLng point2) {
    final lat1 = radians(point1.latitude);
    final lon1 = radians(point1.longitude);
    final lat2 = radians(point2.latitude);
    final lon2 = radians(point2.longitude);

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = degrees(math.atan2(y, x));
    return (bearing + 360) % 360;
  }

  static double _calculateTurnAngle(LatLng p1, LatLng p2, LatLng p3) {
    final bearing1 = _calculateBearing(p1, p2);
    final bearing2 = _calculateBearing(p2, p3);

    var angle = bearing2 - bearing1;

    if (angle > 180) {
      angle -= 360;
    } else if (angle < -180) {
      angle += 360;
    }
    return angle;
  }
}
