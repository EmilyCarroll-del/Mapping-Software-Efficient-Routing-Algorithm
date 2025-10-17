// lib/services/google_api_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:graph_go/firebase_options.dart';
import '../models/place_suggestion.dart';

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

/// Parsed place details returned by Google Places Details API.
class ParsedPlace {
  final LatLng latLng;                   // coordinates of the place
  final Map<String, String> components;  // address component type -> value
  ParsedPlace({required this.latLng, required this.components});
}

class GoogleApiService {
  final String key = DefaultFirebaseOptions.currentPlatform.apiKey;

  void _ensureKey() {
    if (key.isEmpty) {
      throw Exception('API key is missing from firebase_options.dart');
    }
  }

  // ---------------- Geocoding ----------------

  Future<LatLng?> geocodeAddress(String address) async {
    _ensureKey();
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {'address': address, 'key': key},
    );
    
    debugPrint('Geocoding Request URI: $uri');

    try {
      final res = await http.get(uri);

      debugPrint('Geocoding Response Code: ${res.statusCode}');
      debugPrint('Geocoding Response Body: ${res.body}');

      if (res.statusCode != 200) return null;

      final data = json.decode(res.body);
      if (data['status'] != 'OK' || (data['results'] as List).isEmpty) {
        debugPrint('Geocoding error: ${data['status']}, ${data['error_message']}');
        return null;
      }

      final loc = data['results'][0]['geometry']['location'];
      return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
    } catch (e) {
      debugPrint('Error in geocodeAddress: $e');
      return null;
    }
  }

  /// Geocode many addresses sequentially (friendlier to rate limits).
  Future<Map<String, LatLng?>> geocodeAddresses(List<String> addresses) async {
    final Map<String, LatLng?> out = {};
    for (final a in addresses) {
      out[a] = await geocodeAddress(a);
    }
    return out;
  }

  /// Distance Matrix (durations in seconds). Returns matrix[i][j] or large = unreachable.
  Future<List<List<int>>> getDistanceMatrix(
      List<LatLng> origins, {
        String travelMode = 'driving',
      }) async {
    _ensureKey();
    final originStr = origins.map((o) => '${o.lat},${o.lng}').join('|');
    final destinationStr = originStr; // origins==destinations for full matrix

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/distancematrix/json',
      {
        'origins': originStr,
        'destinations': destinationStr,
        'mode': travelMode,
        'units': 'metric',
        'key': key,
      },
    );
    
    debugPrint('DistanceMatrix Request URI: $uri');

    try {
      final res = await http.get(uri);
      
      debugPrint('DistanceMatrix Response Code: ${res.statusCode}');
      debugPrint('DistanceMatrix Response Body: ${res.body}');

      if (res.statusCode != 200) {
        throw Exception('DistanceMatrix failed: ${res.statusCode}');
      }
      final data = json.decode(res.body);
      if (data['status'] != 'OK') {
        final errorMessage = data['error_message'] ?? 'No error message provided.';
        throw Exception('DistanceMatrix response: ${data['status']} - $errorMessage');
      }

      final rows = data['rows'] as List;
      final n = rows.length;
      final List<List<int>> matrix = List.generate(n, (_) => List.filled(n, 1 << 30));
      for (int i = 0; i < n; i++) {
        final elements = rows[i]['elements'] as List;
        for (int j = 0; j < elements.length; j++) {
          final el = elements[j];
          if (el['status'] == 'OK' && el['duration'] != null) {
            matrix[i][j] = (el['duration']['value'] as num).toInt(); // seconds
          } else {
            matrix[i][j] = 1 << 30; // unreachable sentinel
             debugPrint('Warning: Unreachable route between origin $i and destination $j. Status: ${el['status']}');
          }
        }
      }
      return matrix;
    } catch (e) {
      debugPrint('Error in getDistanceMatrix: $e');
      rethrow;
    }
  }

  // ---------------- Places Autocomplete ----------------

  /// Get Google Places autocomplete suggestions for an input string.
  Future<List<PlaceSuggestion>> placeAutocomplete(
      String input, {
        String? sessionToken,
        String country = 'us', // optional filter
      }) async {
    _ensureKey();
    final params = <String, String>{
      'input': input,
      'key': key,
      if (sessionToken != null) 'sessiontoken': sessionToken,
      'components': 'country:$country',
      // You can add 'types': 'address' to bias toward addresses only.
    };

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );

    final res = await http.get(uri);
    final data = json.decode(res.body);

    final status = data['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('Places Autocomplete error: $status');
    }

    final List predictions = data['predictions'] ?? const [];
    return predictions
        .map((p) => PlaceSuggestion(
      description: p['description'] as String,
      placeId: p['place_id'] as String,
    ))
        .toList()
        .cast<PlaceSuggestion>();
  }

  /// Get details for a placeId: coordinates + address components.
  Future<ParsedPlace> placeDetails(String placeId, {String? sessionToken}) async {
    _ensureKey();
    final params = <String, String>{
      'place_id': placeId,
      'key': key,
      if (sessionToken != null) 'sessiontoken': sessionToken,
      'fields': 'address_component,geometry',
    };

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      params,
    );

    final res = await http.get(uri);
    final data = json.decode(res.body);

    final status = data['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status != 'OK') {
      throw Exception('Place Details error: $status');
    }

    final result = data['result'];
    final loc = result['geometry']['location'];
    final latLng = LatLng(
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );

    final comps = <String, String>{};
    for (final comp in (result['address_components'] as List)) {
      final types = (comp['types'] as List).cast<String>();
      final value = comp['long_name'] as String;
      for (final t in types) {
        // last write wins; good enough for typical cases
        comps[t] = value;
      }
    }

    return ParsedPlace(latLng: latLng, components: comps);
  }
}
