import 'package:flutter/material.dart';
import '../models/delivery_address.dart';
import '../models/digraph.dart';
import '../services/google_api_service.dart';

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


  // ===== T7 / Routing Graph Fields =====
  final GoogleApiService apiService;

  GraphProvider({GoogleApiService? apiService})
    : apiService = apiService ?? GoogleApiService();
  // _api = GoogleApiService();


  List<DeliveryAddress> addresses = [];
  Digraph? graph;
  List<List<int>>? matrix;

// ===== T7 Methods =====
  /// Build the routing graph from delivery addresses
  Future<void> buildGraphFromAddresses(List<DeliveryAddress> input) async {
    addresses = input;

    // 1) Geocode addresses using fullAddress getter
    final fullAddresses = addresses.map((a) => a.fullAddress).toList();
    final geocodeMap = await apiService.geocodeAddresses(fullAddresses);

    // Update latitude / longitude in DeliveryAddress objects
    for (int i = 0; i < addresses.length; i++) {
      final loc = geocodeMap[fullAddresses[i]];
      if (loc != null) {
        addresses[i].latitude = loc.lat;
        addresses[i].longitude = loc.lng;
      } else {
        addresses[i].latitude = null;
        addresses[i].longitude = null;
      }
    }

    // Filter valid addresses
    final valid = addresses.where((a) => a.hasCoordinates).toList();
    final origins = valid.map((a) => LatLng(a.latitude!, a.longitude!)).toList();

    // 2) Distance matrix
    matrix = await apiService.getDistanceMatrix(origins);

    // 3) Build digraph for routing
    graph = Digraph(origins.length);
    for (int i = 0; i < origins.length; i++) {
      for (int j = 0; j < origins.length; j++) {
        if (i == j) continue;
        final w = matrix![i][j];
        if (w < (1 << 29)) {
          graph!.addEdge(i, j, w);
        }
      }
    }

    notifyListeners();
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


