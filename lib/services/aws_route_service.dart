import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/delivery_address.dart';
import '../models/route_optimization.dart';
import 'turn_by_turn_service.dart';

class NotInitializedError extends Error {}

class AWSRouteService {
  String? _apiKey;
  String? _region;
  String? _calculatorName;
  bool _isInitialized = false;

  AWSRouteService();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await dotenv.load(fileName: ".env");
      _apiKey = dotenv.env['AWS_API_KEY'];
      _region = dotenv.env['AWS_REGION'];
      _calculatorName = dotenv.env['AWS_CALCULATOR_NAME'];

      if (_apiKey == null || _region == null || _calculatorName == null) {
        _isInitialized = false;
        print(
            '❌ AWS credentials not found in .env file. Please check your configuration.');
        throw Exception(
            'AWS credentials not found in .env file. Please check your configuration.');
      }
      _isInitialized = true;
      print('✅ AWS Route Service Initialized');
    } catch (e) {
      print('❌ Error initializing AWS Route Service: $e');
      _isInitialized = false;
    }
  }

  bool get isAvailable => _isInitialized;

  Future<RouteOptimization> calculateRoute({
    required List<DeliveryAddress> addresses,
    required String travelMode,
  }) async {
    if (!isAvailable) {
      // throw NotInitializedError(); // Re-enable this once initialization is stable
      print('⚠️ AWS service was not initialized. Attempting to initialize now...');
      await initialize();
      if (!isAvailable) {
        throw Exception('Failed to initialize AWS Service on the fly.');
      }
    }

    if (addresses.length < 2) {
      throw Exception(
          'At least two addresses (departure and destination) are required.');
    }

    final departure = addresses.first;
    final destination = addresses.last;
    final waypoints = addresses.length > 2
        ? addresses.sublist(1, addresses.length - 1)
        : <DeliveryAddress>[];

    final endpoint =
        'https://routes.geo.$_region.amazonaws.com/routes/v0/calculators/$_calculatorName/calculate/route?key=$_apiKey';

    final payload = {
      'DeparturePosition': [departure.longitude, departure.latitude],
      'DestinationPosition': [destination.longitude, destination.latitude],
      if (waypoints.isNotEmpty)
        'WaypointPositions':
            waypoints.map((w) => [w.longitude, w.latitude]).toList(),
      'TravelMode': travelMode,
      if (travelMode == 'Truck')
        'TruckModeOptions': {
          'AvoidFerries': true,
          'AvoidTolls': false,
          'Dimensions': {
            'Height': 4.2,
            'Length': 22.0,
            'Width': 2.6,
            'Unit': 'Meters'
          },
          'Weight': {'Total': 36000, 'Unit': 'Kilograms'}
        },
      'IncludeLegGeometry': true,
      'DepartNow': true,
      'DistanceUnit': 'Kilometers',
    };

    print('🌎 AWS RouteService → Sending request to: $endpoint');
    print('📤 Payload: ${jsonEncode(payload)}'); // Use jsonEncode for cleaner printing

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      print('📥 AWS Response Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ AWS Error body: ${response.body}');
        throw Exception(
            'AWS API error (${response.statusCode}): ${response.body}');
      }

      final responseBody = jsonDecode(response.body);

      if (!responseBody.containsKey('Summary') ||
          !responseBody.containsKey('Legs')) {
        throw Exception(
            'AWS response is missing required fields. Full body: ${response.body}');
      }

      return await _parseRouteResponse(responseBody, addresses);
    } catch (e) {
      print('❌ Exception during AWS route request: $e');
      throw Exception('Error calculating route: $e');
    }
  }

  Future<RouteOptimization> _parseRouteResponse(
      Map<String, dynamic> responseBody,
      List<DeliveryAddress> originalAddresses) async {
    print('🔍 Parsing AWS route response...');

    final summary = responseBody['Summary'];
    final awsLegs = responseBody['Legs'] as List;

    List<List<double>> fullGeometry = [];
    List<RouteStep> majorLegs = [];
    int legSequence = 0;

    majorLegs.add(RouteStep(
      sequenceNumber: legSequence++,
      address: originalAddresses.first,
      instructions: 'Starting Point',
    ));

    for (int i = 0; i < awsLegs.length; i++) {
      final leg = awsLegs[i];
      final legGeometry = leg['Geometry']['LineString'] as List;

      fullGeometry.addAll(legGeometry
          .map((p) => (p as List).map<double>((c) => c.toDouble()).toList()));

      majorLegs.add(
        RouteStep(
          sequenceNumber: legSequence++,
          address: originalAddresses[i + 1],
          instructions: 'Stop ${i + 1}',
          distanceFromPrevious: (leg['Distance'] as num).toDouble(),
          estimatedTravelTime:
              Duration(seconds: (leg['DurationSeconds'] as num).round()),
        ),
      );
    }

    print('🧭 Generating turn-by-turn steps...');

    final routePoints = fullGeometry.map((p) => LatLng(p[1], p[0])).toList();

    final detailedSteps = await TurnByTurnService.generateSteps(routePoints);

    final flippedGeometry = fullGeometry.map((p) => [p[1], p[0]]).toList();

    print('✅ Route parsed successfully!');

    return RouteOptimization(
      name: 'AWS Optimized Route',
      addresses: originalAddresses,
      algorithm: RouteAlgorithm.aws,
      totalDistance: (summary['Distance'] as num).toDouble(),
      estimatedTime:
          Duration(seconds: (summary['DurationSeconds'] as num).round()),
      routeGeometry: flippedGeometry,
      detailedSteps: detailedSteps,
      legs: majorLegs,
      completedAt: DateTime.now(),
    );
  }
}
