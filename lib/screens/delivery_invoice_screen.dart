import 'package:flutter/material.dart';
import '../models/route_optimization.dart';
import '../models/order_model.dart' as app_order;

class DeliveryInvoiceScreen extends StatelessWidget {
  final app_order.OrderModel order;
  final RouteOptimization routeOptimization;
  final Duration actualDuration;
  final DateTime startTime;
  final DateTime endTime;

  const DeliveryInvoiceScreen({
    super.key,
    required this.order,
    required this.routeOptimization,
    required this.actualDuration,
    required this.startTime,
    required this.endTime,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Invoice'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Delivery Completed!'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop('completed');
              },
              child: const Text('Back to Assignments'),
            ),
          ],
        ),
      ),
    );
  }
}
