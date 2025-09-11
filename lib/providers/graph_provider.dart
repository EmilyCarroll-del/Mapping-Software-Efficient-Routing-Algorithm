import 'package:flutter/material.dart';

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
}
