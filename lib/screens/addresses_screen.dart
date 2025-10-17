import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/delivery_address.dart';
import '../models/place_suggestion.dart';
import '../providers/delivery_provider.dart';
import '../services/geocoding_service.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _searchCtrl = TextEditingController();
  final _sessionToken = const Uuid().v4();

  Timer? _debounce;
  bool _adding = false;
  List<PlaceSuggestion> _suggestions = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final q = text.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      try {
        // Use the new static method from GeocodingService
        final r = await GeocodingService.placeAutocomplete(q, sessionToken: _sessionToken);
        if (mounted) setState(() => _suggestions = r);
      } catch (e) {
        // If Places is restricted or fails, just hide suggestions
        if (mounted) setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _addFromSuggestion(PlaceSuggestion s) async {
    setState(() => _adding = true);
    try {
      // Use the new static method from GeocodingService
      final detail = await GeocodingService.placeDetails(s.placeId, sessionToken: _sessionToken);

      // Parse address parts from components
      final c = detail.components;
      final streetNumber = c['street_number'] ?? '';
      final route = c['route'] ?? '';
      final street = (streetNumber + ' ' + route).trim();
      final city = c['locality'] ?? c['sublocality'] ?? c['postal_town'] ?? '';
      final state = c['administrative_area_level_1'] ?? '';
      final zip = c['postal_code'] ?? '';

      final addr = DeliveryAddress(
        streetAddress: street.isEmpty ? s.description : street,
        city: city,
        state: state,
        zipCode: zip,
        // Adapt to the new ParsedPlace structure
        latitude: detail.latitude,
        longitude: detail.longitude,
      );

      await context.read<DeliveryProvider>().addAddress(addr);
      if (!mounted) return;
      _searchCtrl.clear();
      setState(() => _suggestions = []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addTypedAddress() async {
    final free = _searchCtrl.text.trim();
    if (free.isEmpty) return;

    setState(() => _adding = true);
    try {
      // Create a temporary address and geocode it with the new service
      final tempAddr = DeliveryAddress(streetAddress: free, city: '', state: '', zipCode: '');
      final geocodedAddr = await GeocodingService.geocodeAddress(tempAddr);

      await context.read<DeliveryProvider>().addAddress(geocodedAddr);
      if (!mounted) return;
      _searchCtrl.clear();
      setState(() => _suggestions = []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e')),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dp = context.watch<DeliveryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Addresses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search address',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _adding
                        ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                        : (_searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _suggestions = []);
                      },
                    )),
                    border: const OutlineInputBorder(),
                  ),
                ),

                // If there are suggestions, show the suggestions list
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(8),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(s.description),
                          onTap: () => _addFromSuggestion(s),
                        );
                      },
                    ),
                  ),
                ],

                // If no suggestions but there is text, allow adding the typed address
                if (_suggestions.isEmpty && _searchCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: Text("Add '${_searchCtrl.text.trim()}'"),
                      onPressed: _adding ? null : _addTypedAddress,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Saved addresses list
          Expanded(
            child: ListView.builder(
              itemCount: dp.addresses.length,
              itemBuilder: (context, i) {
                final a = dp.addresses[i];
                return ListTile(
                  title: Text(a.fullAddress),
                  subtitle: Text(a.hasCoordinates ? 'Geocoded' : 'Pending geocode'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => dp.removeAddress(a.id),
                  ),
                );
              },
            ),
          ),

          // Optimize button (needs at least 2 addresses: start + 1 stop)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.route),
                label: const Text('Optimize on Map'),
                onPressed: dp.addresses.length < 2
                    ? null
                    : () => context.go('/graph'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
