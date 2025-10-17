import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../models/delivery_address.dart';
import '../models/place_suggestion.dart';

// A local, private class to handle Place Details data without external dependencies.
class ParsedPlace {
  final double latitude;
  final double longitude;
  final Map<String, String> components;
  ParsedPlace({required this.latitude, required this.longitude, required this.components});
}

class GeocodingService {
  static const String _googleMapsApiKey = 'AIzaSyD2jr77VpYOfumEdOn2uOlKTwAUY6RbWl8';
  static const String _googleGeocodingUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

  /// Convert a delivery address to GPS coordinates
  static Future<DeliveryAddress> geocodeAddress(DeliveryAddress address) async {
    try {
      final locations = await locationFromAddress(address.fullAddress);
      if (locations.isNotEmpty) {
        final location = locations.first;
        return address.copyWith(
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }
    } catch (e) {
      print('Geocoding package failed: $e');
    }

    try {
      return await _geocodeWithGoogle(address);
    } catch (e) {
      print('Google Geocoding API failed: $e');
      throw Exception('Failed to geocode address: ${address.fullAddress}');
    }
  }

  /// Batch geocode multiple addresses
  static Future<List<DeliveryAddress>> geocodeAddresses(
    List<DeliveryAddress> addresses,
  ) async {
    final results = <DeliveryAddress>[];
    for (final address in addresses) {
      try {
        final geocodedAddress = await geocodeAddress(address);
        results.add(geocodedAddress);
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('Failed to geocode ${address.fullAddress}: $e');
        results.add(address);
      }
    }
    return results;
  }

  /// Get Google Places autocomplete suggestions for an input string.
  static Future<List<PlaceSuggestion>> placeAutocomplete(
      String input, {
        String? sessionToken,
        String country = 'us',
      }) async {
    final params = <String, String>{
      'input': input,
      'key': _googleMapsApiKey,
      if (sessionToken != null) 'sessiontoken': sessionToken,
      'components': 'country:$country',
    };
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', params);
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
        .toList();
  }

  /// Get details for a placeId: coordinates + address components.
  static Future<ParsedPlace> placeDetails(String placeId, {String? sessionToken}) async {
    final params = <String, String>{
      'place_id': placeId,
      'key': _googleMapsApiKey,
      if (sessionToken != null) 'sessiontoken': sessionToken,
      'fields': 'address_component,geometry',
    };
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', params);
    final res = await http.get(uri);
    final data = json.decode(res.body);

    final status = data['status'] as String? ?? 'UNKNOWN_ERROR';
    if (status != 'OK') {
      throw Exception('Place Details error: $status');
    }

    final result = data['result'];
    final loc = result['geometry']['location'];
    final latitude = (loc['lat'] as num).toDouble();
    final longitude = (loc['lng'] as num).toDouble();

    final comps = <String, String>{};
    for (final comp in (result['address_components'] as List)) {
      final types = (comp['types'] as List).cast<String>();
      final value = comp['long_name'] as String;
      for (final t in types) {
        comps[t] = value;
      }
    }

    return ParsedPlace(latitude: latitude, longitude: longitude, components: comps);
  }

  static Future<String> reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        return '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea} ${placemark.postalCode}';
      }
    } catch (e) {
      print('Reverse geocoding failed: $e');
    }
    return 'Unknown Location';
  }

  static Future<DeliveryAddress> _geocodeWithGoogle(DeliveryAddress address) async {
    final url = Uri.parse('$_googleGeocodingUrl?address=${Uri.encodeComponent(address.fullAddress)}&key=$_googleMapsApiKey');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        final result = data['results'][0];
        final location = result['geometry']['location'];
        return address.copyWith(
          latitude: location['lat'].toDouble(),
          longitude: location['lng'].toDouble(),
        );
      } else {
        throw Exception('Google Geocoding API error: ${data['status']}');
      }
    } else {
      throw Exception('HTTP error: ${response.statusCode}');
    }
  }

  static bool isValidAddressFormat(String address) {
    final parts = address.split(',').map((s) => s.trim()).toList();
    return parts.length >= 2;
  }

  static Map<String, String> parseAddress(String fullAddress) {
    final parts = fullAddress.split(',').map((s) => s.trim()).toList();
    if (parts.length < 2) throw Exception('Invalid address format');
    final streetAddress = parts[0];
    final city = parts[1];
    String state = '';
    String zipCode = '';
    if (parts.length >= 3) {
      final stateZip = parts[2].split(' ');
      if (stateZip.length >= 2) {
        state = stateZip[0];
        zipCode = stateZip[1];
      } else {
        state = parts[2];
      }
    }
    return {
      'streetAddress': streetAddress,
      'city': city,
      'state': state,
      'zipCode': zipCode,
    };
  }

  static Future<Map<String, Map<String, double>>> getDistanceMatrix(
    List<DeliveryAddress> addresses,
  ) async {
    final distanceMatrix = <String, Map<String, double>>{};
    for (int i = 0; i < addresses.length; i++) {
      final fromAddress = addresses[i];
      distanceMatrix[fromAddress.id] = <String, double>{};
      for (int j = 0; j < addresses.length; j++) {
        if (i == j) {
          distanceMatrix[fromAddress.id]![addresses[j].id] = 0.0;
        } else {
          final toAddress = addresses[j];
          if (fromAddress.hasCoordinates && toAddress.hasCoordinates) {
            final distance = _calculateHaversineDistance(
              fromAddress.latitude!,
              fromAddress.longitude!,
              toAddress.latitude!,
              toAddress.longitude!,
            );
            distanceMatrix[fromAddress.id]![toAddress.id] = distance;
          } else {
            distanceMatrix[fromAddress.id]![toAddress.id] = double.infinity;
          }
        }
      }
    }
    return distanceMatrix;
  }

  static double _calculateHaversineDistance(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const double earthRadius = 6371;
    final dLat = (lat2 - lat1).toRadians();
    final dLon = (lon2 - lon1).toRadians();
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1.toRadians()) * cos(lat2.toRadians()) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
}

extension DoubleExtensions on double {
  double toRadians() => this * (pi / 180);
}
