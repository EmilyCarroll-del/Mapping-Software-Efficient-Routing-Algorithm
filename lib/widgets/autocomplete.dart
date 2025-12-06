import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class AddressSuggestion {
  final String description;
  final String placeId;
  AddressSuggestion({required this.description, required this.placeId});
}

class PlaceDetail {
  final String formattedAddress;
  final double lat;
  final double lng;
  final Map<String, String>? addressComponents; // street, city, state, zipCode, country
  
  PlaceDetail({
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    this.addressComponents,
  });
}

class AddressAutocompleteField extends StatefulWidget {
  final String apiKey;
  final void Function(PlaceDetail) onSelected;
  final String? countryCode;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;

  const AddressAutocompleteField({
    super.key,
    required this.apiKey,
    required this.onSelected,
    this.countryCode,
    this.controller,
    this.onSubmitted,
  });

  @override
  State<AddressAutocompleteField> createState() => _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  late TextEditingController _controller;
  bool _isLocalController = false;
  final _uuid = const Uuid();
  String _sessionToken = '';
  String? _errorMessage;
  bool _isProgrammaticTextChange = false;
  bool _suggestionWasSelected = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController();
      _isLocalController = true;
    } else {
      _controller = widget.controller!;
    }
    _sessionToken = _uuid.v4();
  }

  @override
  void dispose() {
    if (_isLocalController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<List<AddressSuggestion>> _fetchSuggestions(String input) async {
    if (_isProgrammaticTextChange) {
      _isProgrammaticTextChange = false;
      return [];
    }

    if (!kIsWeb || input.isEmpty) return [];
    
    try {
      // Properly construct URI with encoded parameters
      final queryParams = <String, String>{
        'input': input,
        'sessiontoken': _sessionToken,
      };
      // Only add country if specified (null = search globally like Google Maps)
      if (widget.countryCode != null && widget.countryCode!.isNotEmpty) {
        queryParams['country'] = widget.countryCode!;
      } else {
        queryParams['country'] = 'none'; // Signal to server to not restrict by country
      }
      
      final uri = Uri.parse('http://localhost:3000/places/autocomplete').replace(
        queryParameters: queryParams,
      );

      final res = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Autocomplete request timed out');
          return http.Response('{"status":"TIMEOUT"}', 408);
        },
      ).catchError((e) {
        debugPrint('HTTP fetch error: $e');
        if (e is! http.Response) {
          return http.Response('{"status":"FETCH_ERROR", "error_message":"${e.toString()}"}', 520);
        }
        return e;
      });

      if (res.statusCode != 200) {
        debugPrint('Places HTTP ${res.statusCode}: ${res.body}');
        // Check if server is not running
        if (res.statusCode == 0 || res.statusCode == 520) {
          debugPrint('⚠️ Server may not be running at http://localhost:3000');
          debugPrint('   Start the server with: node server/index.cjs');
          if (mounted) {
            setState(() {
              _errorMessage = 'Server not running. Start with: node server/index.cjs';
            });
          }
        }
        return [];
      }
      
      // Clear error on success
      if (mounted && _errorMessage != null) {
        setState(() {
          _errorMessage = null;
        });
      }
      
      final data = json.decode(res.body) as Map<String, dynamic>;
      
      if (data['status'] != 'OK') {
        final errorMsg = data['error_message'] ?? data['message'] ?? 'Unknown error';
        debugPrint('Places status ${data['status']}: $errorMsg');
        
        // Provide helpful error messages
        if (data['status'] == 'ERROR' && errorMsg.toString().contains('PLACES_API_KEY')) {
          debugPrint('⚠️ PLACES_API_KEY not set in server environment variables');
          if (mounted) {
            setState(() {
              _errorMessage = 'API key not configured on server';
            });
          }
        }
        return [];
      }
      
      final preds = data['predictions'] as List<dynamic>?;
      if (preds == null || preds.isEmpty) {
        return [];
      }
      
      // Filter to only show real addresses (geocode, street_address, premise, establishment)
      // Exclude routes, intersections, and other non-deliverable locations
      final validTypes = ['geocode', 'street_address', 'premise', 'establishment', 'subpremise'];
      final filtered = preds.where((p) {
        final pMap = p as Map<String, dynamic>;
        final types = pMap['types'] as List<dynamic>?;
        if (types == null) return false;
        
        // Check if any of the valid types are present
        final hasValidType = types.any((type) => validTypes.contains(type));
        
        // Exclude routes and intersections (these are not deliverable addresses)
        final isRoute = types.contains('route');
        final isIntersection = types.contains('intersection');
        
        return hasValidType && !isRoute && !isIntersection;
      }).toList();
      
      // Limit to top 5 suggestions to reduce clutter
      final limited = filtered.take(5).toList();
      
      return limited.map((p) {
        final pMap = p as Map<String, dynamic>;
        return AddressSuggestion(
          description: pMap['description'] as String? ?? '',
          placeId: pMap['place_id'] as String? ?? '',
        );
      }).toList();
    } catch (e, stackTrace) {
      debugPrint('Exception in _fetchSuggestions: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  Future<PlaceDetail?> _fetchPlaceDetail(String placeId) async {
    if (!kIsWeb || placeId.isEmpty) return null;
    
    try {
      final uri = Uri.parse('http://localhost:3000/places/details').replace(
        queryParameters: {
          'place_id': placeId,
          'sessiontoken': _sessionToken,
        },
      );

      final res = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Place details request timed out');
          return http.Response('{"status":"TIMEOUT"}', 408);
        },
      ).catchError((e) {
        debugPrint('Place details HTTP error: $e');
        return http.Response('{"status":"FETCH_ERROR"}', 520);
      });

      if (res.statusCode != 200) {
        debugPrint('Place details HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      
      final data = json.decode(res.body) as Map<String, dynamic>;
      
      if (data['status'] != 'OK') {
        final errorMsg = data['error_message'] ?? data['message'] ?? 'Unknown error';
        debugPrint('Place details status ${data['status']}: $errorMsg');
        return null;
      }
      
      final r = data['result'] as Map<String, dynamic>?;
      if (r == null) {
        debugPrint('Place details: result is null');
        return null;
      }
      
      final geometry = r['geometry'] as Map<String, dynamic>?;
      if (geometry == null) {
        debugPrint('Place details: geometry is null');
        return null;
      }
      
      final loc = geometry['location'] as Map<String, dynamic>?;
      if (loc == null) {
        debugPrint('Place details: location is null');
        return null;
      }
      
      final lat = loc['lat'];
      final lng = loc['lng'];
      if (lat == null || lng == null) {
        debugPrint('Place details: lat/lng is null');
        return null;
      }
      
      // Parse address components from Places API
      Map<String, String>? addressComponents;
      final components = r['address_components'] as List<dynamic>?;
      if (components != null) {
        addressComponents = {};
        String? shortStateName; // Store short state name (e.g., "NY") separately
        
        for (final comp in components) {
          final compMap = comp as Map<String, dynamic>;
          final types = compMap['types'] as List<dynamic>?;
          final longName = compMap['long_name'] as String? ?? '';
          final shortName = compMap['short_name'] as String? ?? '';
          
          if (types != null) {
            if (types.contains('street_number')) {
              addressComponents['streetNumber'] = longName;
            } else if (types.contains('route')) {
              addressComponents['street'] = longName;
            } else if (types.contains('locality')) {
              addressComponents['city'] = longName;
            } else if (types.contains('sublocality') || types.contains('sublocality_level_1')) {
              // Use sublocality as city if locality is not available
              if (!addressComponents.containsKey('city')) {
                addressComponents['city'] = longName;
              }
            } else if (types.contains('administrative_area_level_1')) {
              // Prefer short name for state (e.g., "NY" instead of "New York")
              addressComponents['state'] = shortName.isNotEmpty ? shortName : longName;
              shortStateName = shortName.isNotEmpty ? shortName : longName;
            } else if (types.contains('postal_code')) {
              addressComponents['zipCode'] = longName;
            } else if (types.contains('country')) {
              addressComponents['country'] = longName;
            } else if (types.contains('premise') || types.contains('establishment') || types.contains('subpremise')) {
              // For establishments, store the name separately
              if (longName.isNotEmpty) {
                addressComponents['establishmentName'] = longName;
              }
            } else if (types.contains('neighborhood') || types.contains('sublocality_level_2')) {
              // Store neighborhood for context
              if (!addressComponents.containsKey('neighborhood')) {
                addressComponents['neighborhood'] = longName;
              }
            }
          }
        }
        
        // Get place name for establishments
        final placeName = r['name'] as String? ?? '';
        
        // Combine street number and route into streetAddress
        if (addressComponents.containsKey('streetNumber') || addressComponents.containsKey('street')) {
          final streetNumber = addressComponents['streetNumber'] ?? '';
          final street = addressComponents['street'] ?? '';
          String combinedStreet = '$streetNumber $street'.trim();
          
          // For establishments, prepend the establishment name if available
          if (placeName.isNotEmpty && addressComponents.containsKey('establishmentName')) {
            // Use the place name (e.g., "Science and Innovation Center") as the street address
            // This matches how Google Maps displays it
            addressComponents['streetAddress'] = placeName;
            // Store the actual street address separately for reference
            addressComponents['actualStreet'] = combinedStreet;
          } else {
            addressComponents['streetAddress'] = combinedStreet;
          }
          addressComponents.remove('streetNumber');
          addressComponents.remove('street');
        } else if (addressComponents.containsKey('establishmentName') || placeName.isNotEmpty) {
          // For establishments without street address, use establishment/place name
          addressComponents['streetAddress'] = placeName.isNotEmpty ? placeName : addressComponents['establishmentName']!;
          addressComponents.remove('establishmentName');
        }
        
        // If we still don't have a streetAddress, try to extract from formatted_address
        if (!addressComponents.containsKey('streetAddress') || addressComponents['streetAddress']!.isEmpty) {
          final formatted = r['formatted_address'] as String? ?? '';
          if (formatted.isNotEmpty) {
            // Try to parse the first part before the first comma as street address
            final parts = formatted.split(',').map((s) => s.trim()).toList();
            if (parts.isNotEmpty) {
              addressComponents['streetAddress'] = parts[0];
            }
          }
        }
      }
      
      // Get the name and vicinity for better address matching
      final name = r['name'] as String? ?? '';
      final vicinity = r['vicinity'] as String? ?? '';
      final responsePlaceId = r['place_id'] as String? ?? '';
      
      // For establishments, prefer a more specific address if available
      // If we have a vicinity (which is often more specific for establishments),
      // we might want to use it, but formatted_address is usually more complete
      String finalFormattedAddress = r['formatted_address'] as String? ?? '';
      
      // Log all details for debugging
      debugPrint('=== Place Details Response ===');
      debugPrint('Place ID (requested): $placeId');
      debugPrint('Place ID (response): $responsePlaceId');
      debugPrint('Place name: $name');
      debugPrint('Vicinity: $vicinity');
      debugPrint('Formatted address: $finalFormattedAddress');
      debugPrint('Coordinates: (${(lat as num).toDouble()}, ${(lng as num).toDouble()})');
      debugPrint('Address components: $addressComponents');
      debugPrint('================================');
      
      _sessionToken = _uuid.v4(); // new session after selection
      return PlaceDetail(
        formattedAddress: finalFormattedAddress,
        lat: (lat as num).toDouble(),
        lng: (lng as num).toDouble(),
        addressComponents: addressComponents,
      );
    } catch (e, stackTrace) {
      debugPrint('Exception in _fetchPlaceDetail: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TypeAheadField<AddressSuggestion>(
            controller: _controller,
            suggestionsCallback: _fetchSuggestions,
            hideOnEmpty: true,
            hideOnLoading: true,
            debounceDuration: const Duration(milliseconds: 300),
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.text,
                autofillHints: const [],
                enableSuggestions: false,
                autocorrect: false,
                onSubmitted: (value) {
                  if (_suggestionWasSelected) {
                    _suggestionWasSelected = false;
                    return;
                  }
                  widget.onSubmitted?.call(value);
                },
                decoration: InputDecoration(
                  labelText: 'Enter Address',
                  hintText: 'Street, City, State, ZIP Code',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                  errorMaxLines: 2,
                ),
              );
            },
            itemBuilder: (context, s) => SizedBox(
              height: 56,
              child: ListTile(
                leading: const Icon(Icons.place, size: 20),
                title: Text(
                  s.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                dense: true,
              ),
            ),
            onSelected: (s) async {
              _suggestionWasSelected = true;
              FocusScope.of(context).unfocus();

              debugPrint('Selected place: ${s.description}');
              debugPrint('Place ID: ${s.placeId}');

              final detail = await _fetchPlaceDetail(s.placeId);
              if (detail != null) {
                debugPrint('Place Details:');
                debugPrint('  Formatted Address: ${detail.formattedAddress}');
                debugPrint('  Coordinates: (${detail.lat}, ${detail.lng})');
                debugPrint('  Components: ${detail.addressComponents}');

                _isProgrammaticTextChange = true;
                _controller.text = detail.formattedAddress;
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: _controller.text.length),
                );
                widget.onSelected(detail);
              } else {
                debugPrint('Failed to fetch place details for place_id: ${s.placeId}');
              }
            },
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('No matches'),
            ),
            loadingBuilder: (context) => const Padding(
              padding: EdgeInsets.all(12.0),
              child: LinearProgressIndicator(),
            ),
          ),
          if (_errorMessage != null && _errorMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
