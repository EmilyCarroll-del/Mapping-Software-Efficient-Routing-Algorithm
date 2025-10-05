import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/graph_provider.dart';
import '../providers/delivery_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// import '../models/delivery_address.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  bool _isLoading = false;
  String _statusMessage = "";
  List<int> _samplePath = [];
  int _totalNodes = 0;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  Widget build(BuildContext context) {
    final deliveryProvider = Provider.of<DeliveryProvider>(context);
    final graphProvider = Provider.of<GraphProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Graph Visualization'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddNodeDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              graphProvider.clearGraph();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                setState(() {
                  _isLoading = true;
                  _statusMessage = "Building graph...";
                  _samplePath = [];
                  _totalNodes = 0;
                  _markers.clear();
                  _polylines.clear();
                });

                try {
                  // Build graph from addresses
                  await graphProvider.buildGraphFromAddresses(
                      deliveryProvider.addresses);

                  final graph = graphProvider.graph;
                  if (graph != null) {
                    setState(() {
                      _totalNodes = graph.n;

                      if (graph.n >= 2) {
                        final res =
                        graphProvider.shortestRoute(0, graph.n - 1);
                        _samplePath = List<int>.from(res['path']);
                        _statusMessage =
                        "Graph built! Nodes: ${graph.n}";
                      } else {
                        _statusMessage = "Graph built, but not enough nodes";
                      }

                      // Optional: markers for all addresses
                      for (int i = 0; i < deliveryProvider.addresses.length; i++) {
                        final addr = deliveryProvider.addresses[i];
                        if (addr.hasCoordinates) {
                          _markers.add(Marker(
                            markerId: MarkerId(addr.id),
                            position: LatLng(addr.latitude!, addr.longitude!),
                            infoWindow: InfoWindow(title: addr.fullAddress),
                          ));
                        }
                      }

                      // Optional: polyline for sample path
                      if (_samplePath.isNotEmpty) {
                        final points = _samplePath
                            .map((idx) => LatLng(
                            deliveryProvider.addresses[idx].latitude!,
                            deliveryProvider.addresses[idx].longitude!))
                            .toList();
                        _polylines.add(Polyline(
                            polylineId: const PolylineId("sample_path"),
                            points: points,
                            color: Colors.blue,
                            width: 4));
                      }
                    });
                  } else {
                    setState(() {
                      _statusMessage = "Graph could not be built";
                    });
                  }
                } catch (e) {
                  setState(() {
                    _statusMessage = "Error building graph: $e";
                  });
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Build Routes"),
            ),
          ),
          Text(_statusMessage),
          if (_samplePath.isNotEmpty)
            Text("Sample shortest path: $_samplePath"),
          if (_totalNodes > 0) Text("Total nodes: $_totalNodes"),
          const SizedBox(height: 16),
          Expanded(
            child: Consumer<GraphProvider>(
              builder: (context, graphProvider, child) {
                return graphProvider.nodes.isEmpty
                    ? _buildEmptyGraphPlaceholder()
                    : CustomPaint(
                  painter: GraphPainter(
                      graphProvider.nodes, graphProvider.edges),
                  child: Container(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNodeDialog(context),
        tooltip: 'Add Node',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyGraphPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No graph data yet',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add nodes to start building your graph or use "Build Routes"',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  void _showAddNodeDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Node'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter node label',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Provider.of<GraphProvider>(context, listen: false)
                      .addNode(controller.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  GraphPainter(this.nodes, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint nodePaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final Paint edgePaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final startNode = nodes.firstWhere((n) => n.id == edge.fromId);
      final endNode = nodes.firstWhere((n) => n.id == edge.toId);

      canvas.drawLine(
        Offset(startNode.x, startNode.y),
        Offset(endNode.x, endNode.y),
        edgePaint,
      );
    }

    for (final node in nodes) {
      canvas.drawCircle(
        Offset(node.x, node.y),
        20,
        nodePaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          node.x - textPainter.width / 2,
          node.y - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
