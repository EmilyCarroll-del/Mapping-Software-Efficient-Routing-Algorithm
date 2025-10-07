import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/path_result.dart';
import 'graph_provider.dart';
import 'delivery_provider.dart';

/// Assumed public API that your GraphProvider already exposes (or can expose with trivial wrappers):
///
/// - int nearestNodeTo(LatLng p)
///     Return the nodeId of the graph node closest to p (great-circle or euclidean on your map proj)
///
/// - Future<PathResult> shortestPathLatLng(int src, int dst)
///     Compute shortest path using your T8 algorithms and return PathResult with polyline points
///
/// - LatLng nodeToLatLng(int nodeId)
///     Map nodeId -> LatLng (for markers, bounds)
///
/// If your method names differ, tell me the names/signatures and I’ll patch this file for you.
class RouteProvider with ChangeNotifier {
  final GraphProvider graph;
  final DeliveryProvider deliveries;

  RouteProvider({
    required this.graph,
    required this.deliveries,
  });

  /// Computed outputs for the UI
  List<LatLng> _routePolyline = [];
  List<Marker> _markers = [];
  double _totalDistanceMeters = 0.0;
  List<int> _orderedNodeStops = [];
  bool _isComputing = false;
  String _status = '';

  List<LatLng> get routePolyline => _routePolyline;
  List<Marker> get markers => _markers;
  double get totalDistanceMeters => _totalDistanceMeters;
  List<int> get orderedNodeStops => _orderedNodeStops;
  bool get isComputing => _isComputing;
  String get status => _status;

  void _setStatus(String s) {
    _status = s;
    notifyListeners();
  }

  /// Public entry point for T9
  ///
  /// start: required start coordinate (e.g., depot/current location)
  /// stops: list of delivery coordinates (unordered)
  ///
  /// returns the full merged PathResult polyline and metadata exposed via getters.
  Future<void> computeEfficientRoute({
    required LatLng start,
    required List<LatLng> stops,
    bool improveWith2Opt = true,
  }) async {
    if (stops.isEmpty) {
      _setStatus('No stops provided.');
      return;
    }

    _isComputing = true;
    _routePolyline = [];
    _markers = [];
    _totalDistanceMeters = 0.0;
    _orderedNodeStops = [];
    notifyListeners();

    try {
      _setStatus('Snapping points to graph…');

      // 1) Snap all coordinates to nearest nodes in the graph
      final int startNode = graph.nearestNodeTo(start);
      final List<int> stopNodes = stops.map(graph.nearestNodeTo).toList();

      // 2) Order stops with Nearest Neighbor (from start), optionally 2-opt refine
      _setStatus('Building stop order…');
      final ordered = _nearestNeighborOrder(startNode, stopNodes.toList()); // copy
      final orderedImproved = improveWith2Opt
          ? _twoOpt(ordered, distance: _graphDistance)
          : ordered;

      _orderedNodeStops = [startNode, ...orderedImproved];

      // 3) Stitch shortest paths between consecutive nodes
      _setStatus('Computing shortest paths between legs…');
      final List<LatLng> merged = [];
      double totalMeters = 0.0;

      for (int i = 0; i < _orderedNodeStops.length - 1; i++) {
        final a = _orderedNodeStops[i];
        final b = _orderedNodeStops[i + 1];

        final PathResult leg = await graph.shortestPathLatLng(a, b);
        if (leg.points.isEmpty) {
          throw Exception('No path between nodes $a and $b');
        }

        // Append, avoiding duplicate joining point
        if (merged.isNotEmpty) {
          merged.addAll(leg.points.skip(1));
        } else {
          merged.addAll(leg.points);
        }
        totalMeters += leg.distanceMeters;
      }

      _routePolyline = merged;
      _totalDistanceMeters = totalMeters;

      // 4) Build markers for start + ordered stops
      _markers = _buildMarkers(_orderedNodeStops);

      _setStatus('Route ready: ${(totalMeters / 1000).toStringAsFixed(2)} km');

    } catch (e) {
      _setStatus('Route error: $e');
      rethrow;
    } finally {
      _isComputing = false;
      notifyListeners();
    }
  }

  /// ---------- Heuristics & Helpers ----------

  /// Nearest Neighbor ordering from a startNode over the pool of stop nodes
  List<int> _nearestNeighborOrder(int startNode, List<int> remaining) {
    final List<int> order = [];
    int current = startNode;

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) =>
          _graphDistance(current, a).compareTo(_graphDistance(current, b)));
      final next = remaining.removeAt(0);
      order.add(next);
      current = next;
    }
    return order;
  }

  /// Simple distance proxy using straight-line (Haversine via LatLng) for speed
  /// during ordering. Shortest-path distance is computed later per leg.
  double _graphDistance(int u, int v) {
    final p = graph.nodeToLatLng(u);
    final q = graph.nodeToLatLng(v);
    return _haversineMeters(p, q);
  }

  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h = pow(sin(dLat / 2), 2) +
        cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
    return 2 * R * asin(min(1, sqrt(h)));
  }

  double _deg2rad(double d) => d * (pi / 180.0);

  /// 2-opt tour improvement on sequence [start, s1, s2, ..., sn]
  /// Note: we only optimize the stop sublist; start node remains at index 0.
  List<int> _twoOpt(List<int> order, {required double Function(int,int) distance}) {
    if (order.length < 3) return order;
    bool improved = true;
    final List<int> best = List<int>.from(order);

    double tourLen(List<int> seq) {
      double sum = 0;
      int prev = _orderedNodeStops.isEmpty ? -1 : _orderedNodeStops.first; // start node if available later
      prev = prev == -1 ? seq.first : prev;
      // We only compare relative; use straight-line proxy
      int current = prev;
      for (final x in seq) {
        sum += distance(current, x);
        current = x;
      }
      return sum;
    }

    while (improved) {
      improved = false;
      for (int i = 0; i < best.length - 2; i++) {
        for (int k = i + 1; k < best.length - 1; k++) {
          final candidate = List<int>.from(best);
          candidate.setRange(i, k + 1, best.sublist(i, k + 1).reversed);
          if (tourLen(candidate) + 1e-6 < tourLen(best)) {
            best
              ..clear()
              ..addAll(candidate);
            improved = true;
          }
        }
      }
    }
    return best;
  }

  List<Marker> _buildMarkers(List<int> orderedNodes) {
    final List<Marker> result = [];
    for (int i = 0; i < orderedNodes.length; i++) {
      final nodeId = orderedNodes[i];
      final pos = graph.nodeToLatLng(nodeId);

      final isStart = i == 0;
      final label = isStart ? 'START' : '$i';

      result.add(
        Marker(
          markerId: MarkerId('node_$nodeId'),
          position: pos,
          infoWindow: InfoWindow(title: label),
        ),
      );
    }
    return result;
  }
}
