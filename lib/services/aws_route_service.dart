
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:aws_common/aws_common.dart';

import '../models/delivery_address.dart';
import '../models/route_optimization.dart';

class AWSRouteService {
  final String? _apiKey = dotenv.env['AWS_API_KEY'];
  final String? _region = dotenv.env['AWS_REGION'];
  final String? _calculatorName = dotenv.env['AWS_CALCULATOR_NAME'];

  Future<RouteOptimization> calculateRoute({
    required List<DeliveryAddress> addresses,
    required String travelMode, // e.g., 'Car', 'Truck', 'Walking'
    Map<String, double>? truckOptions,
  }) async {
    if (_apiKey == null || _region == null || _calculatorName == null) {
      throw Exception('AWS configuration not found in .env file.');
    }
    if (addresses.length < 2) {
      throw Exception('At least two addresses are required to calculate a route.');
    }

    final uri = Uri.parse('https://routes.geo.$_region.amazonaws.com/routes/v1/calculators/$_calculatorName/calculate-route');

    final departurePosition = [addresses.first.longitude, addresses.first.latitude];
    final destinationPosition = [addresses.last.longitude, addresses.last.latitude];

    final List<List<double>> waypointPositions = addresses.length > 2
        ? addresses.sublist(1, addresses.length - 1).map((a) => [a.longitude!, a.latitude!]).toList()
        : [];

    final Map<String, dynamic> body = {
      'DeparturePosition': departurePosition,
      'DestinationPosition': destinationPosition,
      'TravelMode': travelMode,
      'DepartNow': true, // Use current time for traffic estimation
      'IncludeLegs': true,
      'IncludeSteps': true,
    };

    if (waypointPositions.isNotEmpty) {
      body['WaypointPositions'] = waypointPositions;
    }

    // --- CORRECTLY ADD TRUCK OPTIONS ---
    if (travelMode == 'Truck') {
      body['TruckModeOptions'] = {
        'AvoidFerries': true,
        'AvoidTolls': false,
        'Dimensions': {
          'Height': 4.0,
          'Length': 12.0,
          'Width': 2.5,
          'Unit': 'Meters'
        },
        'Weight': {
          'Total': 30000,
          'Unit': 'Kilograms'
        }
      };
    }

    final request = AWSHttpRequest(
      method: AWSHttpMethod.post,
      uri: uri,
      headers: {
        'x-api-key': _apiKey!,
        'Content-Type': 'application/json',
      },
      body: utf8.encode(json.encode(body)),
    );

    final signer = AWSSigV4Signer(
      credentialsProvider: const AWSCredentialsProvider(AWSCredentials('', '')), // Anonymous credentials for API Key
    );
    final signedRequest = await signer.sign(request, credentialScope: AWSCredentialScope(region: _region!, service: AWSService.geo));

    final response = await http.post(
      signedRequest.uri,
      headers: signedRequest.headers,
      body: signedRequest.body,
    );

    if (response.statusCode == 200) {
      final responseBody = json.decode(response.body);
      return RouteOptimization.fromAwsJson(responseBody, addresses, travelMode);
    } else {
      throw Exception('Failed to calculate route: ${response.body}');
    }
  }
}
