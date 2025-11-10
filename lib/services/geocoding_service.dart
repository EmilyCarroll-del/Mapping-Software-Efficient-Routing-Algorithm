import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../models/delivery_address.dart';

class GeocodingService {
  static const String _googleMapsApiKey = 'AIzaSyD2jr77VpYOfumEdOn2uOlKTwAUY6RbWl8';
  static const String _googleGeocodingUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

  /// Convert a delivery address to GPS coordinates
  static Future<DeliveryAddress> geocodeAddress(DeliveryAddress address) async {
    final street = address.streetAddress.trim();
    final city = address.city.trim();
    final state = address.state.trim();
    final zip = address.zipCode.trim();

    // Build candidate queries from most specific to least
    final List<String> candidates = [];
    final full = _buildQueryFromAddress(address);
    if (full.isNotEmpty) candidates.add(full);
    if (street.isNotEmpty && zip.isNotEmpty) candidates.add('$street, $zip');
    if (street.isNotEmpty && city.isNotEmpty) candidates.add('$street, $city${state.isNotEmpty ? ', $state' : ''}');
    if (city.isNotEmpty && zip.isNotEmpty) candidates.add('$city, $zip');
    if (zip.isNotEmpty) candidates.add(zip);

    // Deduplicate while preserving order
    final seen = <String>{};
    final queries = candidates.where((q) => seen.add(q)).toList();

    // Also try country-appended fallbacks (e.g. add ', USA') to help match
    final List<String> extra = [];
    for (final q in queries) {
      final lower = q.toLowerCase();
      if (!lower.contains('usa') && !lower.contains('united states') && !lower.contains('u.s.')) {
        extra.add('$q, USA');
      }
    }
    for (final q in extra) {
      if (seen.add(q)) queries.add(q);
    }

    if (queries.isEmpty) {
      print('geocodeAddress: no valid address parts for id=${address.id}, skipping geocode');
      return address;
    }

    for (final q in queries) {
      try {
        // small delay to reduce chance of rate-limiting when called in loops
        await Future.delayed(const Duration(milliseconds: 120));
        final result = await _geocodeWithGoogle(address, query: q);
        if (result.hasCoordinates) return result;
        // otherwise continue to next candidate
      } catch (e, st) {
        print('Geocoding attempt failed for id=${address.id} query="$q": $e\n$st');
        // try next
      }
    }

    // none of the queries returned coordinates
    print('Geocoding failed for all queries for id=${address.id} candidates=${queries}');
    return address;
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
        
        // Add delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('Failed to geocode ${address.fullAddress}: $e');
        results.add(address); // Keep original address if geocoding fails
      }
    }
    
    return results;
  }

  /// Reverse geocode: convert GPS coordinates to address
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

  /// Geocode using Google Geocoding API
  static Future<DeliveryAddress> _geocodeWithGoogle(DeliveryAddress address, {String? query}) async {
     final q = (query == null || query.trim().isEmpty) ? address.fullAddress : query;
     final url = Uri.parse('$_googleGeocodingUrl?address=${Uri.encodeComponent(q)}&key=$_googleMapsApiKey');

     final response = await http.get(url);

     if (response.statusCode != 200) {
      print('Google Geocoding HTTP error ${response.statusCode} for query="$q": ${response.body}');
      return address; // return original address on HTTP error
    }

    dynamic data;
    try {
      data = json.decode(response.body);
    } catch (e) {
      print('Failed to decode Google Geocoding response for query="$q": ${e}');
      print('Raw response: ${response.body}');
      return address;
    }

    final status = data is Map && data['status'] != null ? data['status'].toString() : 'UNKNOWN';
    if (status != 'OK') {
      print('Google Geocoding API returned status=$status for query="$q": ${response.body}');
      return address;
    }

    final results = (data as Map)['results'];
    if (results == null || results is! List || results.isEmpty) {
      print('Google Geocoding API returned no results for query="$q": ${response.body}');
      return address;
    }

    final result = results[0];
    if (result == null || result is! Map) {
      print('Google Geocoding API result malformed for query="$q": ${response.body}');
      return address;
    }

    final geometry = result['geometry'];
    if (geometry == null || geometry is! Map) {
      print('Google Geocoding API geometry missing for query="$q": ${response.body}');
      return address;
    }

    final location = geometry['location'];
    if (location == null || location is! Map) {
      print('Google Geocoding API location missing for query="$q": ${response.body}');
      return address;
    }

    final lat = location['lat'];
    final lng = location['lng'];
    if (lat == null || lng == null) {
      print('Google Geocoding API lat/lng missing for query="$q": ${response.body}');
      return address;
    }

    try {
      final doubleLat = (lat as num).toDouble();
      final doubleLng = (lng as num).toDouble();
      return address.copyWith(latitude: doubleLat, longitude: doubleLng);
    } catch (e) {
      print('Failed to parse lat/lng for query="$q": ${e}');
      print('Location payload: $location');
      return address;
    }
  }

  static String _buildQueryFromAddress(DeliveryAddress address) {
    final parts = <String>[];

    String normalizeStreet(String s) {
      var t = s.trim();
      // Convert hyphenated house numbers (e.g. 70-30) to '70 30'
      t = t.replaceAllMapped(RegExp(r'(\d+)-(\d+)'), (m) => '${m[1]} ${m[2]}');
      // Remove extra punctuation except commas (we use commas to separate parts)
      t = t.replaceAll(RegExp(r'[/\:;#]'), '');
      return t;
    }

    String normalizeZip(String? z) {
      if (z == null) return '';
      final digits = RegExp(r'\d{5}').firstMatch(z);
      if (digits != null) return digits.group(0)!;
      // fallback: strip non-digits
      return z.replaceAll(RegExp(r'[^0-9]'), '');
    }

    void addIfValid(String? s, {bool isZip = false}) {
      if (s == null) return;
      final raw = s.trim();
      if (raw.isEmpty) return;
      if (raw.toLowerCase() == 'null') return;
      final val = isZip ? normalizeZip(raw) : normalizeStreet(raw);
      if (val.isEmpty) return;
      parts.add(val);
    }

    addIfValid(address.streetAddress);
    addIfValid(address.city);
    addIfValid(address.state);
    addIfValid(address.zipCode, isZip: true);

    return parts.join(', ');
  }

  /// Validate if an address format is correct
  static bool isValidAddressFormat(String address) {
    // Basic validation - check if address has minimum required components
    final parts = address.split(',').map((s) => s.trim()).toList();
    return parts.length >= 2; // At least street and city
  }

  /// Parse address string into components
  static Map<String, String> parseAddress(String fullAddress) {
    final parts = fullAddress.split(',').map((s) => s.trim()).toList();
    
    if (parts.length < 2) {
      throw Exception('Invalid address format');
    }
    
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

  /// Get distance matrix between multiple addresses
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
              fromAddress.latitude!, fromAddress.longitude!,
              toAddress.latitude!, toAddress.longitude!,
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

  /// Calculate Haversine distance between two GPS coordinates
  static double _calculateHaversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1.toRadians()) * cos(lat2.toRadians()) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }
}

extension DoubleExtensions on double {
  double toRadians() => this * (3.14159265359 / 180);
}
