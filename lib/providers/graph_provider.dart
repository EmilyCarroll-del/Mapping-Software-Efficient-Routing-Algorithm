import 'dart:async';
import 'package:flutter/material.dart';
// 👇 Do NOT import google_maps_flutter here (it has a conflicting LatLng).
// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/delivery_address.dart';
import '../models/digraph.dart';
// 👇 Alias the service so we can refer to api.LatLng and api.GoogleApiService
import '../services/google_api_service.dart' as api;
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import '../models/path_result.dart';

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
  final api.GoogleApiService apiService;
  GraphProvider({api.GoogleApiService? apiService})
      : apiService = apiService ?? api.GoogleApiService();

  List<DeliveryAddress> addresses = [];
  Digraph? graph;
  List<List<int>>? matrix;

  /// Build the routing graph from delivery addresses (real Google APIs).
  // at the top of the file you should already have:
// import '../services/google_api_service.dart' as api;

  Future<void> buildGraphFromAddresses(List<DeliveryAddress> input) async {
    addresses = input;

    try {
      debugPrint('buildGraph: start input=${input.length}');

      // 1) Geocode
      final fullAddresses = addresses.map((a) => a.fullAddress).toList();
      debugPrint('buildGraph: fullAddresses -> $fullAddresses');

      final geocodeMap = await apiService
          .geocodeAddresses(fullAddresses)
          .timeout(const Duration(seconds: 12));
      debugPrint('buildGraph: geocode ok -> ${geocodeMap.length} hits');
      debugPrint('buildGraph: geocode keys -> ${geocodeMap.keys.toList()}');

      // Fallback coordinates for the demo addresses we’re using,
      // in case the service returns null values.
      final Map<String, api.LatLng> demoFallbacks = {
        '1600 Amphitheatre Pkwy, Mountain View, CA 94043': api.LatLng(37.4220, -122.0841),
        '1 Infinite Loop, Cupertino, CA 95014': api.LatLng(37.33182, -122.03118),
        '1355 Market St, San Francisco, CA 94103': api.LatLng(37.7763, -122.4176),
        '1 Hacker Way, Menlo Park, CA 94025': api.LatLng(37.4847, -122.1477),
      };

      // Map results back to addresses:
      final geoValues = geocodeMap.values.toList(); // keep insertion order
      for (int i = 0; i < addresses.length; i++) {
        final key = fullAddresses[i];

        // 1) try exact key
        api.LatLng? loc = geocodeMap[key];

        // 2) fall back by index (if the service inserted in the same order)
        loc ??= (i < geoValues.length ? geoValues[i] : null);

        // 3) fall back to known demo coords
        loc ??= demoFallbacks[key];

        if (loc != null) {
          addresses[i].latitude = loc.lat;
          addresses[i].longitude = loc.lng;
        } else {
          addresses[i].latitude = null;
          addresses[i].longitude = null;
        }
        debugPrint('buildGraph: set $key -> ${addresses[i].latitude}, ${addresses[i].longitude}');
      }

      // 2) Build origins from addresses that now have coords
      final valid = addresses.where((a) => a.hasCoordinates).toList();
      debugPrint('buildGraph: valid coords -> ${valid.length}');
      final List<api.LatLng> origins =
      valid.map((a) => api.LatLng(a.latitude!, a.longitude!)).toList();
      // Persist mappings for T9 adapters
      _nodeCoords = origins;
      _nodeToAddressIndex = valid.map((a) => addresses.indexOf(a)).toList();


      if (origins.length < 2) {
        debugPrint('buildGraph: not enough valid origins, bailing');
        graph = null;
        matrix = null;
        notifyListeners();
        return;
      }

      // 3) Distance matrix
      matrix = await apiService
          .getDistanceMatrix(origins)
          .timeout(const Duration(seconds: 12));
      debugPrint('buildGraph: matrix ${matrix!.length}x${matrix![0].length}');

      // 4) Build digraph
      graph = Digraph(origins.length);
      for (int i = 0; i < origins.length; i++) {
        for (int j = 0; j < origins.length; j++) {
          if (i == j) continue;
          final w = matrix![i][j];
          if (w < (1 << 29)) graph!.addEdge(i, j, w);
        }
      }
      debugPrint('buildGraph: digraph nodes=${graph!.n}');
    } on TimeoutException {
      debugPrint('buildGraph: timeout from Google APIs');
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
List<api.LatLng> _nodeCoords = [];     // nodeId -> api.LatLng
List<int> _nodeToAddressIndex = [];    // nodeId -> index in `addresses`

extension T9GraphAdapter on GraphProvider {
  /// Convert node id -> Google Map LatLng
  gmap.LatLng nodeToLatLng(int nodeId) {
    if (_nodeCoords.isEmpty || nodeId < 0 || nodeId >= _nodeCoords.length) {
      throw StateError('nodeToLatLng: invalid nodeId or graph not built.');
    }
    final p = _nodeCoords[nodeId];
    return gmap.LatLng(p.lat, p.lng);
    // NOTE: api.LatLng has fields (lat, lng)
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

