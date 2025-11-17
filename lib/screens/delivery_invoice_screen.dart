import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order.dart' as app_order;
import '../models/route_optimization.dart';
import '../providers/delivery_provider.dart';

class DeliveryInvoiceScreen extends StatefulWidget {
  final app_order.Order order;
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
  State<DeliveryInvoiceScreen> createState() => _DeliveryInvoiceScreenState();
}

class _DeliveryInvoiceScreenState extends State<DeliveryInvoiceScreen> {
  bool _isCompleting = false;
  bool _completed = false;
  String? _errorMessage;

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy – h:mm a').format(dateTime);
  }

  Future<void> _completeDelivery() async {
    if (_isCompleting || _completed) return;

    setState(() {
      _isCompleting = true;
      _errorMessage = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection(widget.order.sourceCollection)
          .doc(widget.order.id)
          .update({
        'status': 'completed',
        'completedAt': Timestamp.fromDate(widget.endTime),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualDurationSeconds': widget.actualDuration.inSeconds,
        if (widget.routeOptimization.estimatedTime != null)
          'estimatedDurationSeconds':
              widget.routeOptimization.estimatedTime!.inSeconds,
        if (widget.routeOptimization.totalDistance != null)
          'totalDistanceKm': widget.routeOptimization.totalDistance,
      });

      if (!mounted) return;

      context
          .read<DeliveryProvider>()
          .removeAssignedOrderLocally(widget.order.id);

      setState(() {
        _isCompleting = false;
        _completed = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery marked as completed.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCompleting = false;
        _errorMessage = 'Failed to update delivery status. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimated = widget.routeOptimization.estimatedTime;
    // --- MODIFICATION: Skip the first stop (Hofstra) for UI display ---
    final displaySteps = widget.routeOptimization.optimizedRoute != null &&
            widget.routeOptimization.optimizedRoute!.length > 1
        ? widget.routeOptimization.optimizedRoute!.sublist(1)
        : <RouteStep>[];
    final distanceKm = widget.routeOptimization.totalDistance ?? 0;
    final primaryText =
        _completed ? 'Back to Assigned Orders' : 'Complete Order';
    final primaryAction = _completed
        ? () {
            Navigator.of(context).pop('completed');
          }
        : (_isCompleting ? null : _completeDelivery);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Invoice'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryCard(
                actualDuration: widget.actualDuration,
                estimatedDuration: estimated,
                distanceKm: distanceKm,
                startTime: widget.startTime,
                endTime: widget.endTime,
                formatter: _formatDuration,
                dateFormatter: _formatDateTime,
              ),
              const SizedBox(height: 16),
              _StopsCard(steps: displaySteps), // Use the modified list
              const SizedBox(height: 16),
              _DetailsCard(order: widget.order),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton(
            onPressed: primaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D2B0D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isCompleting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    primaryText,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Duration actualDuration;
  final Duration? estimatedDuration;
  final double distanceKm;
  final DateTime startTime;
  final DateTime endTime;
  final String Function(Duration) formatter;
  final String Function(DateTime) dateFormatter;

  const _SummaryCard({
    required this.actualDuration,
    required this.estimatedDuration,
    required this.distanceKm,
    required this.startTime,
    required this.endTime,
    required this.formatter,
    required this.dateFormatter,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Color(0xFF0D2B0D)),
                const SizedBox(width: 8),
                Text(
                  'Delivery Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryRow(
              label: 'Total Distance',
              value: '${distanceKm.toStringAsFixed(1)} km',
            ),
            _SummaryRow(
              label: 'Estimated Duration',
              value: estimatedDuration != null
                  ? formatter(estimatedDuration!)
                  : 'N/A',
            ),
            _SummaryRow(
              label: 'Actual Duration',
              value: formatter(actualDuration),
            ),
            _SummaryRow(
              label: 'Started',
              value: dateFormatter(startTime),
            ),
            _SummaryRow(
              label: 'Completed',
              value: dateFormatter(endTime),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsCard extends StatelessWidget {
  final List<RouteStep> steps;

  const _StopsCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF0D2B0D)),
                const SizedBox(width: 8),
                Text(
                  'Stops',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (steps.isEmpty)
              const Text('No route details available.')
            else
              ...steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                
                final isPickup = index == 0;
                final isFinal = index == steps.length - 1;
                final title = isPickup
                    ? 'Pickup'
                    : (isFinal
                        ? 'Final Dropoff'
                        : 'Stop ${index + 1}');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isPickup
                          ? Colors.green
                          : (isFinal ? Colors.red : Colors.blue),
                      child: Text(
                        (index + 1).toString(), // Display numbers 1, 2, 3...
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(step.address.fullAddress),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (step.instructions != null &&
                            step.instructions!.isNotEmpty)
                          Text(step.instructions!),
                        if (step.notes != null && step.notes!.isNotEmpty)
                          Text('Notes: ${step.notes!}'),
                        if (step.distanceFromPrevious != null)
                          Text(
                              '${step.distanceFromPrevious!.toStringAsFixed(1)} km from previous stop'),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final app_order.Order order;

  const _DetailsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment, color: Color(0xFF0D2B0D)),
                const SizedBox(width: 8),
                Text(
                  'Delivery Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow(
              'Dispatcher',
              order.pickupAddress.notes?.isNotEmpty == true
                  ? order.pickupAddress.notes!
                  : 'Not specified',
            ),
            _detailRow(
              'Receiver',
              order.dropOffAddresses.isNotEmpty &&
                      order.dropOffAddresses.first.notes?.isNotEmpty == true
                  ? order.dropOffAddresses.first.notes!
                  : 'Not specified',
            ),
            _detailRow('Delivery Notes', order.notes ?? 'None provided'),
            _detailRow('Pickup Created',
                DateFormat('MMM d, yyyy – h:mm a').format(order.createdAt)),
            const SizedBox(height: 8),
            _detailRow('Pickup Address', order.pickupAddress.fullAddress),
            const SizedBox(height: 8),
            Text(
              'Drop-off Addresses',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (order.dropOffAddresses.isEmpty)
              const Text('None supplied.')
            else
              ...order.dropOffAddresses.asMap().entries.map(
                (entry) {
                  final index = entry.key + 1;
                  final address = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$index. ${address.fullAddress}',
                      style: const TextStyle(color: Colors.black87),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
