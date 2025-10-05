// lib/models/digraph.dart
class Edge {
  final int to;
  final int weight; // seconds
  Edge(this.to, this.weight);
}

class Digraph {
  final int n; // number of nodes
  final List<List<Edge>> adj;

  Digraph(this.n) : adj = List.generate(n, (_) => []);

  void addEdge(int u, int v, int w) {
    adj[u].add(Edge(v, w));
  }

  /// Basic Dijkstra returning predecessor and distance arrays
  Map<String, dynamic> dijkstra(int source) {
    final dist = List<int>.filled(n, 1 << 30);
    final prev = List<int?>.filled(n, null);
    dist[source] = 0;

    final visited = List<bool>.filled(n, false);
    for (int i = 0; i < n; i++) {
      int u = -1;
      int best = 1 << 30;
      for (int v = 0; v < n; v++) {
        if (!visited[v] && dist[v] < best) {
          best = dist[v];
          u = v;
        }
      }
      if (u == -1) break;
      visited[u] = true;
      for (final e in adj[u]) {
        final alt = dist[u] + e.weight;
        if (alt < dist[e.to]) {
          dist[e.to] = alt;
          prev[e.to] = u;
        }
      }
    }
    return {'dist': dist, 'prev': prev};
  }

  List<int> reconstructPath(int source, int target, List<int?> prev) {
    final path = <int>[];
    for (int? v = target; v != null; v = prev[v]) {
      path.insert(0, v);
      if (v == source) break;
    }
    if (path.isEmpty || path.first != source) return [];
    return path;
  }
}
