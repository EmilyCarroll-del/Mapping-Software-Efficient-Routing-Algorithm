// lib/screens/graph_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/delivery_provider.dart';
import '../providers/graph_provider.dart';
import '../providers/route_provider.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  GoogleMapController? _map;

  // Fallback camera (NYC). The map will auto-fit after a route is drawn.
  final CameraPosition _initial = const CameraPosition(
    target: LatLng(40.7128, -74.0060),
    zoom: 12,
  );

  Future<void> _fitToPolyline(List<LatLng> pts) async {
    if (_map == null || pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _map!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
  }

  @override
  Widget build(BuildContext context) {
    // Only watch the RouteProvider so the map updates when the route changes.
    final routeProv = context.watch<RouteProvider>();

    final polylines = {
      if (routeProv.routePolyline.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('efficient_route'),
          points: routeProv.routePolyline,
          width: 6,
        ),
    };

    final markers = routeProv.markers.toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Efficient Route & Visualization'),
      ),
      body: Column(
        children: [
          if (routeProv.status.isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(routeProv.status),
            ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initial,
              onMapCreated: (c) => _map = c,
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              compassEnabled: true,
            ),
          ),
          _bottomBar(context, routeProv),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, RouteProvider routeProv) {
    // We read the other providers INSIDE the handler (no listening) to avoid
    // recreating/disposing RouteProvider during async work.
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                routeProv.totalDistanceMeters == 0
                    ? 'Distance: —'
                    : 'Distance: ${(routeProv.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
              ),
            ),
            FilledButton.icon(
              icon: routeProv.isComputing
                  ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.route),
              label: Text(routeProv.isComputing ? 'Building…' : 'Build Efficient Route'),
              onPressed: routeProv.isComputing
                  ? null
                  : () async {
                // READ providers (don’t watch) to prevent rebuilds mid-computation.
                final graph = context.read<GraphProvider>();
                final deliveries = context.read<DeliveryProvider>();
                final routes = context.read<RouteProvider>();

                // Need at least 2 addresses (start + 1 stop).
                if (deliveries.addresses.length < 2) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add at least two addresses.')),
                  );
                  return;
                }

                // Build the routing graph (geocode missing coords, distance matrix, digraph).
                try {
                  await graph.buildGraphFromAddresses(deliveries.addresses);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to build graph: $e')),
                  );
                  return;
                }

                // Start & stops
                final LatLng start = deliveries.startLocation ??
                    (routes.markers.isNotEmpty
                        ? routes.markers.first.position
                        : _initial.target);
                final List<LatLng> stops = deliveries.stops;

                if (stops.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add at least one stop.')),
                  );
                  return;
                }

                // Compute efficient route and draw
                await routes.computeEfficientRoute(
                  start: start,
                  stops: stops,
                  improveWith2Opt: true,
                );

                if (!mounted) return;
                await _fitToPolyline(routes.routePolyline);

                if (routes.routePolyline.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No path found between some stops.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
