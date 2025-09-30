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
    try {
      // First try using the geocoding package
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

    // Fallback to Google Geocoding API
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
