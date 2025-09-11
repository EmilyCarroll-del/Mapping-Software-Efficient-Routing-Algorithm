import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/graph_provider.dart';

class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            onPressed: () {
              // Add node functionality
              _showAddNodeDialog(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<GraphProvider>(context, listen: false).clearGraph();
            },
          ),
        ],
      ),
      body: Consumer<GraphProvider>(
        builder: (context, graphProvider, child) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (graphProvider.nodes.isEmpty)
                  Column(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No graph data yet',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add nodes to start building your graph',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  )
                else
                  Expanded(
                    child: CustomPaint(
                      painter: GraphPainter(graphProvider.nodes, graphProvider.edges),
                      child: Container(),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Nodes: ${graphProvider.nodes.length}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  'Edges: ${graphProvider.edges.length}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNodeDialog(context),
        tooltip: 'Add Node',
        child: const Icon(Icons.add),
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


    // Draw edges first
    for (final edge in edges) {
      final startNode = nodes.firstWhere((n) => n.id == edge.fromId);
      final endNode = nodes.firstWhere((n) => n.id == edge.toId);
      
      canvas.drawLine(
        Offset(startNode.x, startNode.y),
        Offset(endNode.x, endNode.y),
        edgePaint,
      );
    }

    // Draw nodes
    for (final node in nodes) {
      canvas.drawCircle(
        Offset(node.x, node.y),
        20,
        nodePaint,
      );
      
      // Draw node label
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
