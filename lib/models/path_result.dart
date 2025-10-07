import 'package:google_maps_flutter/google_maps_flutter.dart';

class PathResult {
  final List<int> nodePath;          // node IDs in the graph
  final double distanceMeters;       // polyline length (computed with Haversine)
  final List<LatLng> points;         // LatLng points for the map polyline

  const PathResult({
    required this.nodePath,
    required this.distanceMeters,
    required this.points,
  });
}
