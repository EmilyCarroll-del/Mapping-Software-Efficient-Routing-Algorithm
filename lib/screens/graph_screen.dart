import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/graph_provider.dart';
import '../providers/settings_provider.dart'; // Import SettingsProvider

class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool darkMode = settingsProvider.darkMode;
    final ThemeData currentTheme = Theme.of(context);

    final Color placeholderIconColor = darkMode ? Colors.grey[700]! : Colors.grey[400]!;
    final Color primaryTextColor = darkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor = darkMode ? Colors.grey[400]! : Colors.grey[600]!;
    final Color fabBackgroundColor = darkMode ? Colors.deepPurple.shade300 : Colors.deepPurple;
    final Color fabIconColor = darkMode ? Colors.black : Colors.white;

    return Scaffold(
      // Scaffold background is handled by MaterialApp theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2B0D),
        title: const Text(
          'Graph Visualization',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              _showAddNodeDialog(context, darkMode, currentTheme);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
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
                        color: placeholderIconColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No graph data yet',
                        style: currentTheme.textTheme.headlineSmall?.copyWith(
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add nodes to start building your graph',
                        style: currentTheme.textTheme.bodyMedium?.copyWith(
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  )
                else
                  Expanded(
                    child: CustomPaint(
                      painter: GraphPainter(graphProvider.nodes, graphProvider.edges, darkMode),
                      child: Container(),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Nodes: ${graphProvider.nodes.length}',
                  style: currentTheme.textTheme.bodyLarge?.copyWith(color: primaryTextColor),
                ),
                Text(
                  'Edges: ${graphProvider.edges.length}',
                  style: currentTheme.textTheme.bodyLarge?.copyWith(color: primaryTextColor),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddNodeDialog(context, darkMode, currentTheme),
        tooltip: 'Add Node',
        backgroundColor: fabBackgroundColor,
        child: Icon(Icons.add, color: fabIconColor),
      ),
    );
  }

  void _showAddNodeDialog(BuildContext context, bool darkMode, ThemeData currentTheme) {
    final TextEditingController controller = TextEditingController();
    final Color dialogBackgroundColor = darkMode ? Colors.grey[800]! : Colors.white;
    final Color dialogTextColor = darkMode ? Colors.white : Colors.black87;
    final Color hintTextColor = darkMode ? Colors.grey[400]! : Colors.grey[600]!;
    final Color buttonTextColor = darkMode ? Colors.deepPurple.shade200 : Colors.deepPurple;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBackgroundColor,
          title: Text('Add Node', style: TextStyle(color: dialogTextColor)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: dialogTextColor),
            decoration: InputDecoration(
              hintText: 'Enter node label',
              hintStyle: TextStyle(color: hintTextColor),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: buttonTextColor)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: darkMode ? Colors.deepPurple.shade300 : Colors.deepPurple,
                foregroundColor: darkMode ? Colors.black : Colors.white,
              ),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Provider.of<GraphProvider>(context, listen: false)
                      .addNode(controller.text);
                  Navigator.of(dialogContext).pop();
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
  final bool darkMode;

  GraphPainter(this.nodes, this.edges, this.darkMode);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint nodePaint = Paint()
      ..color = darkMode ? Colors.tealAccent[400]! : Colors.blue // Brighter node for dark mode
      ..style = PaintingStyle.fill;
    
    final Paint edgePaint = Paint()
      ..color = darkMode ? Colors.grey[600]! : Colors.grey // Lighter edge for dark mode
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final Color nodeLabelColor = darkMode ? Colors.black : Colors.white; // Ensure contrast with node color

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
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(color: nodeLabelColor, fontSize: 12),
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is GraphPainter) {
        return oldDelegate.darkMode != darkMode || oldDelegate.nodes != nodes || oldDelegate.edges != edges;
    }
    return true;
  }
}
