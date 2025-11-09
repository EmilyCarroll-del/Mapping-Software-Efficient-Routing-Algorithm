import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/delivery_address.dart';
import '../models/route_optimization.dart';

/// AWS Location Service route calculation service
///
/// This service provides route calculation using AWS Location Service's
/// calculateRoutes API. It supports both API key authentication (recommended)
/// and AWS Signature Version 4 authentication with IAM credentials.
/// Converts AWS responses to the app's RouteOptimization format.
class AwsRouteService {
  static final AwsRouteService _instance = AwsRouteService._internal();
  factory AwsRouteService() => _instance;
  AwsRouteService._internal();

  String? _apiKey;
  String? _accessKeyId;
  String? _secretAccessKey;
  String? _region;
  String? _calculatorName;
  String? _endpointOverride;
  bool _initialized = false;
  bool _useApiKey = false;

  /// Initialize AWS credentials from environment variables
  /// Supports both API key and IAM credential authentication
  Future<void> initialize() async {
    try {
      // Check if dotenv is available
      try {
        // Try to access dotenv to verify it's loaded
        final testValue = dotenv.env['AWS_REGION'];
        print('✅ Dotenv is loaded and accessible');
        print('Dotenv test value (AWS_REGION): $testValue');
      } catch (e) {
        print('❌ Dotenv access failed: $e');
        throw Exception(
            'Dotenv not loaded. Make sure .env file is in pubspec.yaml assets and '
            'dotenv.load() was called in main.dart before using AWS Route Service.');
      }

      _region = dotenv.env['AWS_REGION'] ?? 'us-east-1';
      _calculatorName =
          dotenv.env['AWS_CALCULATOR_NAME'] ?? 'GraphGoRouteCalculator';
      _endpointOverride = dotenv.env['AWS_ENDPOINT_OVERRIDE'];

      print('Initializing AWS Route Service...');
      print('Region: $_region');
      print('Calculator Name: $_calculatorName');
      if (_endpointOverride != null && _endpointOverride!.isNotEmpty) {
        print('Using endpoint override: $_endpointOverride');
      }
      print('Checking for AWS_API_KEY...');

      // Check for API key first (preferred method)
      _apiKey = dotenv.env['AWS_API_KEY'];
      if (_apiKey != null && _apiKey!.isNotEmpty) {
        _useApiKey = true;
        _initialized = true;
        print('✅ Using API key authentication');
        print(
            'API Key found: ${_apiKey!.substring(0, _apiKey!.length > 20 ? 20 : _apiKey!.length)}...');
        return;
      }

      print('AWS_API_KEY not found, checking for IAM credentials...');

      // Fall back to IAM credentials
      _accessKeyId = dotenv.env['AWS_ACCESS_KEY_ID'];
      _secretAccessKey = dotenv.env['AWS_SECRET_ACCESS_KEY'];

      if (_accessKeyId == null || _secretAccessKey == null) {
        final missingVars = <String>[];
        if (_accessKeyId == null) missingVars.add('AWS_ACCESS_KEY_ID');
        if (_secretAccessKey == null) missingVars.add('AWS_SECRET_ACCESS_KEY');

        throw Exception('AWS credentials not found in .env file. '
            'Missing: ${missingVars.join(', ')}. '
            'Please provide either AWS_API_KEY (recommended) '
            'or AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in your .env file.');
      }

      _useApiKey = false;
      _initialized = true;
      print('✅ Using IAM credentials authentication');
      print(
          'Access Key ID: ${_accessKeyId!.substring(0, _accessKeyId!.length > 10 ? 10 : _accessKeyId!.length)}...');
    } catch (e) {
      print('❌ Failed to initialize AWS Route Service: $e');
      print('Stack trace: ${StackTrace.current}');
      throw Exception('Failed to initialize AWS Route Service. $e');
    }
  }

  /// Check if the service is initialized and credentials are available
  bool get isAvailable =>
      _initialized &&
      _calculatorName != null &&
      (_useApiKey
          ? (_apiKey != null && _apiKey!.isNotEmpty)
          : (_accessKeyId != null && _secretAccessKey != null));

  /// Calculate route using AWS Location Service
  ///
  /// [addresses] - List of delivery addresses to include in the route
  /// [startAddress] - Starting point (optional, defaults to first address)
  /// [travelMode] - Travel mode: 'Car', 'Truck', 'Walking' (default: 'Truck')
  /// [optimizationMode] - 'FastestRoute' or 'ShortestRoute' (default: 'FastestRoute')
  /// [departureTime] - Optional departure time for traffic-aware routing
  ///
  /// Returns a RouteOptimization object with AWS-calculated route
  Future<RouteOptimization> calculateRoute({
    required List<DeliveryAddress> addresses,
    DeliveryAddress? startAddress,
    String travelMode = 'Truck',
    String optimizationMode = 'FastestRoute',
    DateTime? departureTime,
  }) async {
    if (!isAvailable) {
      throw Exception(
          'AWS Route Service not initialized. Call initialize() first.');
    }

    if (addresses.isEmpty) {
      throw Exception('At least one address is required for route calculation');
    }

    // Validate all addresses have coordinates
    final addressesWithCoords =
        addresses.where((a) => a.hasCoordinates).toList();
    if (addressesWithCoords.isEmpty) {
      throw Exception(
          'All addresses must have coordinates (latitude/longitude)');
    }

    // Set start address
    final start = startAddress ?? addressesWithCoords.first;
    if (!start.hasCoordinates) {
      throw Exception('Start address must have coordinates');
    }

    // Separate waypoints (all addresses except start and end)
    final waypoints = <List<double>>[];
    final otherAddresses =
        addressesWithCoords.where((a) => a.id != start.id).toList();

    // If we have waypoints, use them; otherwise use start and end
    DeliveryAddress destination;
    if (otherAddresses.length > 1) {
      // Multiple waypoints: use all except last as waypoints, last as destination
      for (int i = 0; i < otherAddresses.length - 1; i++) {
        waypoints
            .add([otherAddresses[i].longitude!, otherAddresses[i].latitude!]);
      }
      destination = otherAddresses.last;
    } else if (otherAddresses.length == 1) {
      // Single destination, no waypoints
      destination = otherAddresses.first;
    } else {
      // Only start address, return to start
      destination = start;
    }

    // Prepare request body
    final requestBody = {
      'DeparturePosition': [start.longitude!, start.latitude!],
      'DestinationPosition': [destination.longitude!, destination.latitude!],
      if (waypoints.isNotEmpty) 'Waypoints': waypoints,
      'TravelMode': travelMode,
      'DistanceUnit': 'Kilometers',
      'OptimizationMode': optimizationMode,
      'IncludeLegGeometry': true, // IMPORTANT: Request geometry for map display
      if (departureTime != null)
        'DepartureTime': departureTime.toUtc().toIso8601String(),
    };

    print('📊 Route request: ${waypoints.length + 2} total waypoints');
    print('IncludeLegGeometry: true (for in-app map display)');

    final payload = jsonEncode(requestBody);
    print('📤 Sending request to AWS...');
    print('📦 Request body size: ${payload.length} bytes');

    final primaryUri = _buildEndpointUri(useOverride: false);
    bool attemptedOverride = false;
    try {
      return await _executeAwsRouteRequest(
        uri: primaryUri,
        payload: payload,
        body: requestBody,
        addresses: addresses,
        start: start,
        travelMode: travelMode,
      );
    } on SocketException catch (socketError) {
      print('❌ ========================================');
      print('❌ NETWORK ERROR CALLING AWS');
      print('❌ ========================================');
      print('Error type: ${socketError.runtimeType}');
      print('Error message: $socketError');

      if (_useApiKey &&
          _endpointOverride != null &&
          _endpointOverride!.isNotEmpty) {
        attemptedOverride = true;
        final overrideUri = _buildEndpointUri(useOverride: true);
        print('🔁 Retrying AWS request using endpoint override: $overrideUri');
        print('');
        return await _executeAwsRouteRequest(
          uri: overrideUri,
          payload: payload,
          body: requestBody,
          addresses: addresses,
          start: start,
          travelMode: travelMode,
        );
      }

      throw _dnsFailureException(socketError, suppressBanner: true);
    } on Exception catch (e) {
      print('❌ Network/HTTP error: $e');
      if (!attemptedOverride &&
          _useApiKey &&
          _endpointOverride != null &&
          _endpointOverride!.isNotEmpty &&
          e.toString().contains('Failed host lookup')) {
        final overrideUri = _buildEndpointUri(useOverride: true);
        print('🔁 Retrying AWS request using endpoint override: $overrideUri');
        return await _executeAwsRouteRequest(
          uri: overrideUri,
          payload: payload,
          body: requestBody,
          addresses: addresses,
          start: start,
          travelMode: travelMode,
        );
      }

      if (e.toString().contains('timed out')) {
        print('🔴 REQUEST TIMED OUT');
        throw Exception('AWS request timed out. Check network connection.');
      }
      rethrow;
    }
  }

  Uri _buildEndpointUri({required bool useOverride}) {
    if (useOverride &&
        _useApiKey &&
        _endpointOverride != null &&
        _endpointOverride!.isNotEmpty) {
      final trimmed = _endpointOverride!.trim().replaceAll(RegExp(r'/$'), '');
      return Uri.parse(
          '$trimmed/routes/v0/calculators/$_calculatorName/calculate/route');
    }
    return Uri.parse(
      'https://routes.$_region.amazonaws.com/routes/v0/calculators/$_calculatorName/calculate/route',
    );
  }

  Future<RouteOptimization> _executeAwsRouteRequest({
    required Uri uri,
    required String payload,
    required Map<String, dynamic> body,
    required List<DeliveryAddress> addresses,
    required DeliveryAddress start,
    required String travelMode,
  }) async {
    print('🌐 AWS Endpoint: $uri');
    print('🔑 Using ${_useApiKey ? "API Key" : "IAM"} authentication');

    final headers = _buildHeaders(uri: uri, payload: payload);
    print('📤 Headers: ${headers.keys.join(', ')}');

    final response = await http
        .post(
      uri,
      headers: headers,
      body: payload,
    )
        .timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw Exception(
            'Request timed out after 30 seconds. Check network connectivity.');
      },
    );

    print('📥 AWS API Response Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      print('✅ AWS route calculation successful');
      return _parseAwsResponse(response.body, addresses, start, travelMode);
    } else {
      final errorBody = response.body;
      print('❌ AWS API error (${response.statusCode}): $errorBody');
      throw Exception('AWS API error (${response.statusCode}): $errorBody');
    }
  }

  Map<String, String> _buildHeaders({
    required Uri uri,
    required String payload,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Host': uri.host,
    };

    if (_useApiKey) {
      headers['x-api-key'] = _apiKey!;
    } else {
      final timestamp = DateTime.now().toUtc();
      final dateStamp = _formatDate(timestamp);
      final amzDate = _formatDateTime(timestamp);
      headers['X-Amz-Date'] = amzDate;
      headers['Authorization'] = _createAuthorization(
        method: 'POST',
        uri: uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Amz-Date': amzDate,
        },
        payload: payload,
        dateStamp: dateStamp,
        amzDate: amzDate,
      );
    }

    return headers;
  }

  Exception _dnsFailureException(Object error,
      {bool suppressBanner = false}) {
    print('');
    print('🔴 DNS RESOLUTION FAILED');
    print('The device cannot resolve: routes.$_region.amazonaws.com');
    print('');
    print('SOLUTIONS:');
    print('1. Test on a REAL device (recommended)');
    print(
        '2. Restart emulator with DNS: emulator -avd <name> -dns-server 8.8.8.8');
    print('3. Check network connectivity in emulator settings');
    print('4. Try on mobile hotspot instead of WiFi');
    print('');
    return Exception(
      suppressBanner
          ? 'Fallback route used due to network DNS issue.'
          : 'Cannot reach AWS servers (DNS failure). '
              'Test on a real device or configure emulator DNS per console instructions.',
    );
  }

  /// Parse AWS API response into RouteOptimization format
  RouteOptimization _parseAwsResponse(
    String responseBody,
    List<DeliveryAddress> originalAddresses,
    DeliveryAddress startAddress,
    String travelMode,
  ) {
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final summary = json['Summary'] as Map<String, dynamic>;
      final legs = json['Legs'] as List<dynamic>;

      // Extract total distance and duration
      final totalDistance = (summary['Distance'] as num).toDouble();
      final totalDurationSeconds = (summary['DurationSeconds'] as num).toInt();
      final estimatedTime = Duration(seconds: totalDurationSeconds);

      print('📊 Route summary: ${totalDistance}km, ${totalDurationSeconds}s');
      print('Number of legs: ${legs.length}');

      // Extract route geometry from legs
      final List<List<double>> routeGeometry = [];
      for (final leg in legs) {
        final legData = leg as Map<String, dynamic>;

        // AWS returns LineString geometry in each leg
        if (legData.containsKey('Geometry') && legData['Geometry'] != null) {
          final geometry = legData['Geometry'] as Map<String, dynamic>;
          if (geometry.containsKey('LineString') &&
              geometry['LineString'] != null) {
            final lineString = geometry['LineString'] as List<dynamic>;
            for (final point in lineString) {
              final coords = point as List<dynamic>;
              // AWS returns [longitude, latitude], we store [latitude, longitude]
              routeGeometry.add([
                (coords[1] as num).toDouble(), // latitude
                (coords[0] as num).toDouble(), // longitude
              ]);
            }
          }
        }
      }

      print(
          '✅ Extracted ${routeGeometry.length} geometry points for map polyline');

      // Build route steps from legs
      final routeSteps = <RouteStep>[];

      // Map legs to addresses
      final addressMap = <String, DeliveryAddress>{};
      for (final addr in originalAddresses) {
        addressMap[addr.id] = addr;
      }

      // Process each leg
      int sequenceNumber = 1;
      for (final leg in legs) {
        final legData = leg as Map<String, dynamic>;
        final startPos = legData['StartPosition'] as List<dynamic>;
        final endPos = legData['EndPosition'] as List<dynamic>;
        final legDistance = (legData['Distance'] as num).toDouble();
        final legDurationSeconds = (legData['DurationSeconds'] as num).toInt();

        // Find matching address for this leg
        DeliveryAddress? legAddress;
        final endLat = (endPos[1] as num).toDouble();
        final endLng = (endPos[0] as num).toDouble();

        // Find closest address to this position
        double minDistance = double.infinity;
        for (final addr in originalAddresses) {
          if (addr.hasCoordinates) {
            final dist = _calculateDistance(
              endLat,
              endLng,
              addr.latitude!,
              addr.longitude!,
            );
            if (dist < minDistance) {
              minDistance = dist;
              legAddress = addr;
            }
          }
        }

        if (legAddress != null) {
          routeSteps.add(RouteStep(
            sequenceNumber: sequenceNumber++,
            address: legAddress,
            distanceFromPrevious: legDistance,
            estimatedTravelTime: Duration(seconds: legDurationSeconds),
            instructions: sequenceNumber == 2
                ? 'Start your route at ${legAddress.fullAddress}'
                : 'Deliver to ${legAddress.fullAddress}',
          ));
        }
      }

      // Ensure start address is first
      if (routeSteps.isEmpty ||
          routeSteps.first.address.id != startAddress.id) {
        routeSteps.insert(
            0,
            RouteStep(
              sequenceNumber: 1,
              address: startAddress,
              distanceFromPrevious: 0,
              estimatedTravelTime: const Duration(seconds: 0),
              instructions: 'Start your route at ${startAddress.fullAddress}',
            ));
      }

      // Build optimized address list
      final optimizedAddresses =
          routeSteps.map((step) => step.address).toList();

      print(
          '✅ Route parsing complete with ${routeGeometry.length} geometry points');

      return RouteOptimization(
        name: 'AWS Route ($travelMode)',
        addresses: optimizedAddresses,
        algorithm: RouteAlgorithm.aws,
        optimizedRoute: routeSteps,
        totalDistance: totalDistance,
        estimatedTime: estimatedTime,
        routeGeometry: routeGeometry.isNotEmpty ? routeGeometry : null,
        completedAt: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error parsing AWS response: $e');
      throw Exception('Failed to parse AWS response: $e');
    }
  }

  /// Calculate distance between two coordinates (Haversine formula)
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180);

  /// Create AWS Signature Version 4 authorization header
  String _createAuthorization({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payload,
    required String dateStamp,
    required String amzDate,
  }) {
    // Step 1: Create canonical request
    final canonicalUri = uri.path;
    final canonicalQueryString = uri.query;

    final canonicalHeaders = StringBuffer();
    final signedHeaders = <String>[];
    final sortedHeaders = headers.keys.toList()..sort();

    for (final key in sortedHeaders) {
      final value = headers[key]!.toLowerCase().trim();
      canonicalHeaders.writeln('$key:$value');
      signedHeaders.add(key.toLowerCase());
    }
    canonicalHeaders.writeln('host:${uri.host}');
    signedHeaders.add('host');

    final canonicalHeadersStr = canonicalHeaders.toString();
    final signedHeadersStr = signedHeaders.join(';');

    final payloadHash = sha256.convert(utf8.encode(payload)).toString();

    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeadersStr,
      signedHeadersStr,
      payloadHash,
    ].join('\n');

    // Step 2: Create string to sign
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$_region/geo/aws4_request';
    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();

    final stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');

    // Step 3: Calculate signature
    final kDate = _hmacSha256(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, _region!);
    final kService = _hmacSha256(kRegion, 'geo');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signatureBytes = _hmacSha256(kSigning, stringToSign);
    final signature =
        signatureBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Step 4: Create authorization header
    final credentials = '$_accessKeyId/$credentialScope';
    return '$algorithm Credential=$credentials, SignedHeaders=$signedHeadersStr, Signature=$signature';
  }

  /// HMAC-SHA256 implementation
  List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return digest.bytes;
  }

  /// Format date as YYYYMMDD
  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Format datetime as YYYYMMDDTHHMMSSZ
  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }
}
