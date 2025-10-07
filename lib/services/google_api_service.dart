// lib/services/google_api_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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
  final String key = dotenv.env['WEB_GOOGLE_API_KEY']
      ?? dotenv.env['GOOGLE_MAPS_API_KEY']
      ?? '';

  void _ensureKey() {
    if (key.isEmpty) {
      throw Exception('GOOGLE_MAPS_API_KEY (or WEB_GOOGLE_API_KEY) is missing from .env');
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
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final data = json.decode(res.body);
    if (data['status'] != 'OK' || (data['results'] as List).isEmpty) return null;

    final loc = data['results'][0]['geometry']['location'];
    return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
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

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('DistanceMatrix failed: ${res.statusCode}');
    }
    final data = json.decode(res.body);
    if (data['status'] != 'OK') {
      throw Exception('DistanceMatrix response: ${data['status']}');
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
        }
      }
    }
    return matrix;
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
      print('Places Autocomplete error: $status  ${data['error_message'] ?? ''}');
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
