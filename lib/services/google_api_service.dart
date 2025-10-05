// lib/services/google_api_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

class GoogleApiService {
  final String key = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  Future<LatLng?> geocodeAddress(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?address=$encoded&key=$key',
    );
    final res = await http.get(url);
    if (res.statusCode != 200) return null;
    final data = json.decode(res.body);
    if (data['status'] != 'OK' || (data['results'] as List).isEmpty) return null;
    final loc = data['results'][0]['geometry']['location'];
    return LatLng(loc['lat'], loc['lng']);
  }

  /// Geocode many addresses in parallel (with small concurrency)
  Future<Map<String, LatLng?>> geocodeAddresses(List<String> addresses) async {
    final Map<String, LatLng?> out = {};
    // Simple sequential approach (easier to respect rate limits). You can parallelize (Future.wait) cautiously.
    for (final a in addresses) {
      out[a] = await geocodeAddress(a);
    }
    return out;
  }

  /// Build a distance matrix (durations in seconds). Returns matrix[i][j] = duration (int), or large = unreachable
  Future<List<List<int>>> getDistanceMatrix(List<LatLng> origins, {String travelMode = 'driving'}) async {
    final originStr = origins.map((o) => '${o.lat},${o.lng}').join('|');
    final destinationStr = originStr; // origins==destinations for full matrix
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$originStr'
          '&destinations=$destinationStr'
          '&mode=$travelMode'
          '&units=metric'
          '&key=$key',
    );
    final res = await http.get(url);
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
          matrix[i][j] = el['duration']['value']; // seconds
        } else {
          matrix[i][j] = 1 << 30; // unreachable sentinel
        }
      }
    }
    return matrix;
  }
}
