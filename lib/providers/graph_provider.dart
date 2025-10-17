import 'dart:async';
import 'package:flutter/material.dart';

import '../models/delivery_address.dart';
import '../models/digraph.dart';
import '../services/geocoding_service.dart';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import '../models/path_result.dart';

// Private LatLng class to avoid conflicts and dependency on other services
class _LatLng {
  final double lat;
  final double lng;
  _LatLng(this.lat, this.lng);
}

class GraphNode {
  final String id;
  final String label;
  double x;
  double y;

  GraphNode({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
  });
}

class GraphEdge {
  final String id;
  final String fromId;
  final String toId;

  GraphEdge({
    required this.id,
    required this.fromId,
    required this.toId,
  });
}

class GraphProvider extends ChangeNotifier {
  final List<GraphNode> _nodes = [];
  final List<GraphEdge> _edges = [];
  int _nodeCounter = 0;

  List<GraphNode> get nodes => List.unmodifiable(_nodes);
  List<GraphEdge> get edges => List.unmodifiable(_edges);

  void addNode(String label) {
    final node = GraphNode(
      id: 'node_${_nodeCounter++}',
      label: label,
      x: 100 + (_nodes.length * 50) % 300,
      y: 100 + (_nodes.length * 50) % 300,
    );
    _nodes.add(node);
    notifyListeners();
  }

  void removeNode(String nodeId) {
    _nodes.removeWhere((node) => node.id == nodeId);
    _edges.removeWhere((edge) => edge.fromId == nodeId || edge.toId == nodeId);
    notifyListeners();
  }

  void addEdge(String fromId, String toId) {
    final edge = GraphEdge(
      id: 'edge_${_edges.length}',
      fromId: fromId,
      toId: toId,
    );
    _edges.add(edge);
    notifyListeners();
  }

  void removeEdge(String edgeId) {
    _edges.removeWhere((edge) => edge.id == edgeId);
    notifyListeners();
  }

  void clearGraph() {
    _nodes.clear();
    _edges.clear();
    _nodeCounter = 0;
    notifyListeners();
  }

  void updateNodePosition(String nodeId, double x, double y) {
    final nodeIndex = _nodes.indexWhere((node) => node.id == nodeId);
    if (nodeIndex != -1) {
      _nodes[nodeIndex].x = x;
      _nodes[nodeIndex].y = y;
      notifyListeners();
    }
  }

  // ===== Routing Graph Fields =====
  List<DeliveryAddress> addresses = [];
  Digraph? graph;
  List<List<int>>? matrix;

  /// Build the routing graph from delivery addresses.
  Future<void> buildGraphFromAddresses(List<DeliveryAddress> input) async {
    try {
      debugPrint('buildGraph: start input=${input.length}');

      // 1) Geocode addresses using the new GeocodingService
      addresses = await GeocodingService.geocodeAddresses(input)
          .timeout(const Duration(seconds: 15));

      // 2) Build origins from addresses that now have coords
      final valid = addresses.where((a) => a.hasCoordinates).toList();
      debugPrint('buildGraph: valid coords -> ${valid.length}');
      
      // Persist mappings for T9 adapters
      _nodeCoords = valid.map((a) => _LatLng(a.latitude!, a.longitude!)).toList();
      _nodeToAddressIndex = valid.map((a) => addresses.indexOf(a)).toList();

      if (valid.length < 2) {
        debugPrint('buildGraph: not enough valid origins, bailing');
        graph = null;
        matrix = null;
        notifyListeners();
        return;
      }

      // 3) Get distance matrix from the new service
      final distanceMap = await GeocodingService.getDistanceMatrix(valid);
      
      // 4) Convert the distance map (km) to a time matrix (seconds)
      final n = valid.length;
      matrix = List.generate(n, (_) => List.filled(n, 1 << 30));
      final idToIndex = {for (var i = 0; i < n; i++) valid[i].id: i};

      for (final fromEntry in distanceMap.entries) {
        final fromId = fromEntry.key;
        final i = idToIndex[fromId];
        if (i == null) continue;

        for (final toEntry in fromEntry.value.entries) {
          final toId = toEntry.key;
          final j = idToIndex[toId];
          if (j == null) continue;

          final distanceKm = toEntry.value;
          if (distanceKm.isFinite) {
            // Convert distance (km) to time (seconds). Assume 50 km/h average speed.
            // time_seconds = (distance_km / 50 km/h) * 3600 s/h = distance_km * 72
            matrix![i][j] = (distanceKm * 72).toInt();
          } else {
            matrix![i][j] = 1 << 30; // Use a large number for infinity
          }
        }
      }
      debugPrint('buildGraph: matrix ${matrix!.length}x${matrix![0].length}');

      // 5) Build digraph
      graph = Digraph(n);
      for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
          if (i == j) continue;
          final w = matrix![i][j];
          if (w < (1 << 29)) graph!.addEdge(i, j, w);
        }
      }
      debugPrint('buildGraph: digraph nodes=${graph!.n}');
    } on TimeoutException {
      debugPrint('buildGraph: timeout from Geocoding APIs');
      graph = null;
      matrix = null;
      rethrow;
    } catch (e) {
      debugPrint('buildGraph: error $e');
      graph = null;
      matrix = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Compute shortest route between two nodes in the routing graph
  Map<String, dynamic> shortestRoute(int startIndex, int endIndex) {
    if (graph == null) return {'distanceSeconds': 0, 'path': []};

    final res = graph!.dijkstra(startIndex);
    final prev = res['prev'] as List<int?>;
    final dist = res['dist'] as List<int>;
    final path = graph!.reconstructPath(startIndex, endIndex, prev);

    return {'distanceSeconds': dist[endIndex], 'path': path};
  }
}

// Persisted mapping for T9 once buildGraphFromAddresses() runs
List<_LatLng> _nodeCoords = [];     // nodeId -> _LatLng
List<int> _nodeToAddressIndex = [];    // nodeId -> index in `addresses`

extension T9GraphAdapter on GraphProvider {
  /// Convert node id -> Google Map LatLng
  gmap.LatLng nodeToLatLng(int nodeId) {
    if (_nodeCoords.isEmpty || nodeId < 0 || nodeId >= _nodeCoords.length) {
      throw StateError('nodeToLatLng: invalid nodeId or graph not built.');
    }
    final p = _nodeCoords[nodeId];
    return gmap.LatLng(p.lat, p.lng);
  }

  /// Return the nodeId whose coordinate is closest (great-circle) to [p].
  int nearestNodeTo(gmap.LatLng p) {
    if (_nodeCoords.isEmpty) {
      throw StateError('nearestNodeTo: graph not built yet (no nodes).');
    }
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < _nodeCoords.length; i++) {
      final q = _nodeCoords[i];
      final d = _haversineMeters(p.latitude, p.longitude, q.lat, q.lng);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// Shortest path between two graph node IDs -> PathResult with polyline points.
  Future<PathResult> shortestPathLatLng(int src, int dst) async {
    if (graph == null) {
      throw StateError('shortestPathLatLng: graph not built.');
    }
    final res = shortestRoute(src, dst); // your existing method
    final pathNodes = (res['path'] as List<int>);
    if (pathNodes.isEmpty) {
      return const PathResult(nodePath: [], distanceMeters: 0, points: []);
    }

    // Convert nodes to LatLng polyline and compute length with Haversine.
    final points = <gmap.LatLng>[];
    double meters = 0;
    for (int i = 0; i < pathNodes.length; i++) {
      final id = pathNodes[i];
      final pt = nodeToLatLng(id);
      points.add(pt);
      if (i > 0) {
        final prev = nodeToLatLng(pathNodes[i - 1]);
        meters += _haversineMeters(prev.latitude, prev.longitude, pt.latitude, pt.longitude);
      }
    }

    return PathResult(nodePath: pathNodes, distanceMeters: meters, points: points);
  }

  // --- Haversine ---
  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.asin(math.min(1.0, math.sqrt(a)));
    return R * c;
  }

  double _deg2rad(double d) => d * (math.pi / 180.0);
}
