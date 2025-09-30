import 'dart:math';
import '../models/delivery_address.dart';

class RoutingAlgorithms {
  static const double earthRadius = 6371; // Earth's radius in kilometers

  /// Calculate distance between two GPS coordinates using Haversine formula
  static double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Dijkstra's Algorithm for shortest path
  static List<DeliveryAddress> dijkstraAlgorithm(
    List<DeliveryAddress> addresses,
    DeliveryAddress startAddress,
  ) {
    if (addresses.isEmpty) return [];
    
    final unvisited = Set<DeliveryAddress>.from(addresses);
    final distances = <DeliveryAddress, double>{};
    final previous = <DeliveryAddress, DeliveryAddress?>{};
    
    // Initialize distances
    for (final address in addresses) {
      distances[address] = double.infinity;
      previous[address] = null;
    }
    distances[startAddress] = 0;
    
    while (unvisited.isNotEmpty) {
      final current = _getMinDistanceNode(unvisited, distances);
      unvisited.remove(current);
      
      for (final neighbor in unvisited) {
        if (!neighbor.hasCoordinates || !current.hasCoordinates) continue;
        
        final distance = calculateDistance(
          current.latitude!, current.longitude!,
          neighbor.latitude!, neighbor.longitude!,
        );
        
        final newDistance = distances[current]! + distance;
        if (newDistance < distances[neighbor]!) {
          distances[neighbor] = newDistance;
          previous[neighbor] = current;
        }
      }
    }
    
    return _buildPath(startAddress, addresses, previous);
  }

  /// Prim's Algorithm for Minimum Spanning Tree
  static List<DeliveryAddress> primAlgorithm(
    List<DeliveryAddress> addresses,
    DeliveryAddress startAddress,
  ) {
    if (addresses.isEmpty) return [];
    
    final visited = <DeliveryAddress>{};
    final mst = <DeliveryAddress>[];
    final edges = <_Edge>[];
    
    visited.add(startAddress);
    mst.add(startAddress);
    
    while (visited.length < addresses.length) {
      _Edge? minEdge;
      
      for (final visitedNode in visited) {
        for (final unvisitedNode in addresses.where((a) => !visited.contains(a))) {
          if (!visitedNode.hasCoordinates || !unvisitedNode.hasCoordinates) continue;
          
          final distance = calculateDistance(
            visitedNode.latitude!, visitedNode.longitude!,
            unvisitedNode.latitude!, unvisitedNode.longitude!,
          );
          
          final edge = _Edge(visitedNode, unvisitedNode, distance);
          if (minEdge == null || edge.weight < minEdge.weight) {
            minEdge = edge;
          }
        }
      }
      
      if (minEdge != null) {
        visited.add(minEdge.to);
        mst.add(minEdge.to);
        edges.add(minEdge);
      }
    }
    
    return mst;
  }

  /// Kruskal's Algorithm for Minimum Spanning Tree
  static List<DeliveryAddress> kruskalAlgorithm(
    List<DeliveryAddress> addresses,
    DeliveryAddress startAddress,
  ) {
    if (addresses.isEmpty) return [];
    
    final edges = <_Edge>[];
    
    // Create all possible edges
    for (int i = 0; i < addresses.length; i++) {
      for (int j = i + 1; j < addresses.length; j++) {
        final from = addresses[i];
        final to = addresses[j];
        
        if (!from.hasCoordinates || !to.hasCoordinates) continue;
        
        final distance = calculateDistance(
          from.latitude!, from.longitude!,
          to.latitude!, to.longitude!,
        );
        
        edges.add(_Edge(from, to, distance));
      }
    }
    
    // Sort edges by weight
    edges.sort((a, b) => a.weight.compareTo(b.weight));
    
    final parent = <DeliveryAddress, DeliveryAddress>{};
    final rank = <DeliveryAddress, int>{};
    
    // Initialize parent and rank
    for (final address in addresses) {
      parent[address] = address;
      rank[address] = 0;
    }
    
    final mstEdges = <_Edge>[];
    
    for (final edge in edges) {
      final rootFrom = _findRoot(edge.from, parent);
      final rootTo = _findRoot(edge.to, parent);
      
      if (rootFrom != rootTo) {
        mstEdges.add(edge);
        _union(rootFrom, rootTo, parent, rank);
      }
    }
    
    // Build path starting from startAddress
    return _buildPathFromEdges(startAddress, mstEdges);
  }

  /// Ford-Bellman Algorithm for shortest path (handles negative weights)
  static List<DeliveryAddress> fordBellmanAlgorithm(
    List<DeliveryAddress> addresses,
    DeliveryAddress startAddress,
  ) {
    if (addresses.isEmpty) return [];
    
    final distances = <DeliveryAddress, double>{};
    final previous = <DeliveryAddress, DeliveryAddress?>{};
    
    // Initialize distances
    for (final address in addresses) {
      distances[address] = double.infinity;
      previous[address] = null;
    }
    distances[startAddress] = 0;
    
    // Relax edges V-1 times
    for (int i = 0; i < addresses.length - 1; i++) {
      for (int j = 0; j < addresses.length; j++) {
        for (int k = 0; k < addresses.length; k++) {
          if (j == k) continue;
          
          final from = addresses[j];
          final to = addresses[k];
          
          if (!from.hasCoordinates || !to.hasCoordinates) continue;
          
          final distance = calculateDistance(
            from.latitude!, from.longitude!,
            to.latitude!, to.longitude!,
          );
          
          if (distances[from]! + distance < distances[to]!) {
            distances[to] = distances[from]! + distance;
            previous[to] = from;
          }
        }
      }
    }
    
    return _buildPath(startAddress, addresses, previous);
  }

  /// Nearest Neighbor Heuristic (simple but effective for TSP)
  static List<DeliveryAddress> nearestNeighborAlgorithm(
    List<DeliveryAddress> addresses,
    DeliveryAddress startAddress,
  ) {
    if (addresses.isEmpty) return [];
    
    final unvisited = Set<DeliveryAddress>.from(addresses);
    final route = <DeliveryAddress>[];
    
    unvisited.remove(startAddress);
    route.add(startAddress);
    
    DeliveryAddress current = startAddress;
    
    while (unvisited.isNotEmpty) {
      DeliveryAddress? nearest;
      double minDistance = double.infinity;
      
      for (final address in unvisited) {
        if (!current.hasCoordinates || !address.hasCoordinates) continue;
        
        final distance = calculateDistance(
          current.latitude!, current.longitude!,
          address.latitude!, address.longitude!,
        );
        
        if (distance < minDistance) {
          minDistance = distance;
          nearest = address;
        }
      }
      
      if (nearest != null) {
        route.add(nearest);
        unvisited.remove(nearest);
        current = nearest;
      } else {
        break;
      }
    }
    
    return route;
  }

  // Helper methods
  static DeliveryAddress _getMinDistanceNode(
    Set<DeliveryAddress> unvisited,
    Map<DeliveryAddress, double> distances,
  ) {
    return unvisited.reduce((a, b) => 
      distances[a]! < distances[b]! ? a : b
    );
  }

  static List<DeliveryAddress> _buildPath(
    DeliveryAddress start,
    List<DeliveryAddress> addresses,
    Map<DeliveryAddress, DeliveryAddress?> previous,
  ) {
    final path = <DeliveryAddress>[];
    final visited = <DeliveryAddress>{};
    
    void buildPathRecursive(DeliveryAddress current) {
      if (visited.contains(current)) return;
      visited.add(current);
      
      final prev = previous[current];
      if (prev != null) {
        buildPathRecursive(prev);
      }
      path.add(current);
    }
    
    // Build path from each address
    for (final address in addresses) {
      if (!visited.contains(address)) {
        buildPathRecursive(address);
      }
    }
    
    return path;
  }

  static DeliveryAddress _findRoot(
    DeliveryAddress node,
    Map<DeliveryAddress, DeliveryAddress> parent,
  ) {
    if (parent[node] == node) return node;
    return _findRoot(parent[node]!, parent);
  }

  static void _union(
    DeliveryAddress x,
    DeliveryAddress y,
    Map<DeliveryAddress, DeliveryAddress> parent,
    Map<DeliveryAddress, int> rank,
  ) {
    final rootX = _findRoot(x, parent);
    final rootY = _findRoot(y, parent);
    
    if (rootX != rootY) {
      if (rank[rootX]! < rank[rootY]!) {
        parent[rootX] = rootY;
      } else if (rank[rootX]! > rank[rootY]!) {
        parent[rootY] = rootX;
      } else {
        parent[rootY] = rootX;
        rank[rootX] = rank[rootX]! + 1;
      }
    }
  }

  static List<DeliveryAddress> _buildPathFromEdges(
    DeliveryAddress start,
    List<_Edge> edges,
  ) {
    final adjacencyList = <DeliveryAddress, List<DeliveryAddress>>{};
    
    for (final edge in edges) {
      adjacencyList.putIfAbsent(edge.from, () => []).add(edge.to);
      adjacencyList.putIfAbsent(edge.to, () => []).add(edge.from);
    }
    
    final visited = <DeliveryAddress>{};
    final path = <DeliveryAddress>[];
    
    void dfs(DeliveryAddress current) {
      visited.add(current);
      path.add(current);
      
      final neighbors = adjacencyList[current] ?? [];
      for (final neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          dfs(neighbor);
        }
      }
    }
    
    dfs(start);
    return path;
  }
}

class _Edge {
  final DeliveryAddress from;
  final DeliveryAddress to;
  final double weight;

  _Edge(this.from, this.to, this.weight);
}
