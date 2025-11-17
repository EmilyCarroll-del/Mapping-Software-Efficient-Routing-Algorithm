
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/route_optimization.dart';
import '../models/order.dart' as app_order;
import 'delivery_invoice_screen.dart';

class MockNavigationSimulator {
  final List<LatLng> routePoints;
  final _controller = StreamController<Position>();
  Timer? _timer;
  int _currentIndex = 0;

  MockNavigationSimulator({required this.routePoints});

  Stream<Position> get locationStream => _controller.stream;

  void start() {
    if (routePoints.isEmpty) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_currentIndex < routePoints.length) {
        final point = routePoints[_currentIndex];
        final nextPoint = _currentIndex + 1 < routePoints.length ? routePoints[_currentIndex + 1] : point;
        final heading = _calculateHeading(point, nextPoint);
        
        final distance = Geolocator.distanceBetween(point.latitude, point.longitude, nextPoint.latitude, nextPoint.longitude);
        final speed = distance / 2.0; // distance (m) / 2 (s) = m/s

        final position = Position(
          latitude: point.latitude,
          longitude: point.longitude,
          timestamp: DateTime.now(),
          accuracy: 5.0,
          altitude: 0.0, altitudeAccuracy: 1.0,
          heading: heading, headingAccuracy: 1.0,          
          speed: speed,
          speedAccuracy: 1.0,
        );
        _controller.add(position);
        _currentIndex++;
      } else {
        stop();
      }
    });
  }

  double _calculateHeading(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lon1 = from.longitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final lon2 = to.longitude * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final heading = math.atan2(y, x) * 180 / math.pi;
    return (heading + 360) % 360;
  }

  void stop() {
    _timer?.cancel();
    _controller.close();
  }
}

class NavigationEngine {
  final RouteOptimization route;
  final bool isMock;
  final Function(String) onInstructionChanged;
  final Function(double) onDistanceChanged;
  final Function(Position) onPositionUpdated;

  StreamSubscription<Position>? _positionStream;
  MockNavigationSimulator? _mockSimulator;
  final FlutterTts _flutterTts = FlutterTts();
  Position? _lastKnownPosition;

  int _currentStepIndex = 0; 
  String _currentInstruction = '';
  double _distanceToNextTurn = 0.0;
  
  bool _hasSpokenFar = false;
  bool _hasSpokenNear = false;
  bool _isSpeaking = false;

  static const double _kImminentTurnThreshold = 80.0; 
  static const double _kTurnCompletionThreshold = 25.0; 
  static const double _kSkipFarInstructionThreshold = 150.0; // Approx 500 feet

  NavigationEngine({
    required this.route,
    required this.isMock,
    required this.onInstructionChanged,
    required this.onDistanceChanged,
    required this.onPositionUpdated,
  });

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    if (kIsWeb) return;

    try {
      final voices = await _flutterTts.getVoices as List<dynamic>?;
      if (voices == null) {
        print("TTS: No voices found.");
        return;
      }

      Map<String, String>? selectedVoice;

      if (Platform.isAndroid) {
        final voiceMaps = voices.whereType<Map<String, String>>().toList();

        var highQualityVoices = voiceMaps.where((v) =>
            v['locale'] == 'en-US' &&
            v['name']!.toLowerCase().contains('female') &&
            !v['name']!.toLowerCase().contains('default')).toList();

        if (highQualityVoices.isNotEmpty) {
            highQualityVoices.sort((a, b) => b['name']!.length.compareTo(a['name']!.length));
            selectedVoice = highQualityVoices.first;
        } 
        else {
            final maleVoices = voiceMaps.where((v) =>
                v['locale'] == 'en-US' &&
                v['name']!.toLowerCase().contains('male') &&
                !v['name']!.toLowerCase().contains('default')).toList();

            if (maleVoices.isNotEmpty) {
                maleVoices.sort((a, b) => b['name']!.length.compareTo(a['name']!.length));
                selectedVoice = maleVoices.first;
            }
        }
      }

      if (selectedVoice != null) {
        await _flutterTts.setVoice({'name': selectedVoice['name']!, 'locale': selectedVoice['locale']!});
        print("TTS: Preferred voice selected: ${selectedVoice['name']}");
      } else {
        print("TTS: No preferred voice found, using system default for en-US.");
      }
    } catch (e) {
      print("Error setting TTS voice: $e");
    }
  }

  Future<void> start() async {
    await _initTts();

    if (route.addresses.length > 1) {
      final firstDestination = route.addresses[1];
      final initialMessage = "Starting route to ${firstDestination.fullAddress}";
      onInstructionChanged(initialMessage);
      await _speak(initialMessage);
    }

    await Future.delayed(const Duration(seconds: 4));

    if (isMock) {
      _startMockSimulation();
    } else {
      _startRealGps();
    }
  }

  void _startMockSimulation() {
    final points = route.routeGeometry?.map((p) => LatLng(p[0], p[1])).toList() ?? [];
    _mockSimulator = MockNavigationSimulator(routePoints: points);
    _positionStream = _mockSimulator!.locationStream.listen(_onPositionUpdate);
    _mockSimulator!.start();
  }

  void _startRealGps() {
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Position position) async {
    _lastKnownPosition = position;
    onPositionUpdated(position);

    if (route.detailedSteps.isEmpty || _currentStepIndex >= route.detailedSteps.length) return;

    final currentStep = route.detailedSteps[_currentStepIndex];
    
    if (currentStep.address.hasCoordinates) {
      _distanceToNextTurn = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        currentStep.address.latitude!, currentStep.address.longitude!,
      );
      onDistanceChanged(_distanceToNextTurn);

      if (_distanceToNextTurn < _kTurnCompletionThreshold) {
        _moveToNextStep();
      } else {
        _updateInstruction(distance: _distanceToNextTurn);
        await _handleSpeech(distance: _distanceToNextTurn);
      }
    }
  }

  Future<void> _handleSpeech({required double distance}) async {
    if (_isSpeaking) return;

    String? textToSpeak;

    if (distance > _kImminentTurnThreshold && !_hasSpokenFar) {
      textToSpeak = _currentInstruction;
      _hasSpokenFar = true;
    } 
    else if (distance <= _kImminentTurnThreshold && !_hasSpokenNear) {
      // Use the base instruction when imminent, not the version with distance
      final baseInstruction = route.detailedSteps[_currentStepIndex].instructions ?? "Continue on route";
      textToSpeak = baseInstruction;
      _hasSpokenFar = true; 
      _hasSpokenNear = true;
    }

    if (textToSpeak != null && textToSpeak.isNotEmpty) {
      _isSpeaking = true;
      await _speak(textToSpeak);
      _isSpeaking = false;
    }
  }

  void _moveToNextStep() {
    if (_currentStepIndex < route.detailedSteps.length - 1) {
      _currentStepIndex++;
      _hasSpokenFar = false;
      _hasSpokenNear = false;

      final nextStep = route.detailedSteps[_currentStepIndex];
      if (_lastKnownPosition != null && nextStep.address.hasCoordinates) {
        final distanceToNext = Geolocator.distanceBetween(
          _lastKnownPosition!.latitude, _lastKnownPosition!.longitude,
          nextStep.address.latitude!, nextStep.address.longitude!,
        );

        if (distanceToNext < _kSkipFarInstructionThreshold) {
          print("Short segment detected. Skipping far-away instruction.");
          _hasSpokenFar = true;
        }
      }

      _updateInstruction(); 
    } else {
      _currentInstruction = "You have arrived at your destination.";
      onInstructionChanged(_currentInstruction);
      _speak(_currentInstruction);
      stop();
    }
  }

  void _updateInstruction({double? distance}) {
    if (_currentStepIndex >= route.detailedSteps.length) return;

    final step = route.detailedSteps[_currentStepIndex];
    final baseInstruction = step.instructions ?? "Continue on route";
    String formattedInstruction = baseInstruction;

    if (distance != null && distance > _kImminentTurnThreshold) {
      formattedInstruction = "In ${_formatDistance(distance)}, ${baseInstruction.toLowerCase()}";
    } 

    if (_currentInstruction != formattedInstruction) {
      _currentInstruction = formattedInstruction;
      onInstructionChanged(_currentInstruction);
    }
  }

  String _formatDistance(double meters) {
    const double metersToFeet = 3.28084;
    const double metersToMiles = 0.000621371;

    if (meters < 402) { // Roughly a quarter mile
      final double feet = meters * metersToFeet;
      final roundedFeet = (feet / 10).round() * 10;
      if (roundedFeet == 0) return "less than 10 feet";
      return "${roundedFeet} feet";
    } else {
      final double miles = meters * metersToMiles;
      return "${miles.toStringAsFixed(1)} miles";
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _flutterTts.speak(text);
  }

  void stop() {
    _positionStream?.cancel();
    _mockSimulator?.stop();
    _flutterTts.stop();
  }
}

class NavigationScreen extends StatefulWidget {
  final RouteOptimization routeOptimization;
  final app_order.Order order;

  const NavigationScreen({
    super.key,
    required this.routeOptimization,
    required this.order,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  NavigationEngine? _navigationEngine;

  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  
  String _currentInstruction = "Preparing your route...";
  double _distanceToNextTurn = 0.0;

  final bool _isEmulator = true; 

  @override
  void initState() {
    super.initState();
    _setupMap();
    _startNavigation();
  }

  void _setupMap() {
    final routePoints = widget.routeOptimization.routeGeometry
            ?.map((p) => LatLng(p[0], p[1]))
            .toList() ?? [];

    if (routePoints.isNotEmpty) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue.withOpacity(0.8),
          width: 8,
        ),
      );
    }

    final majorStops = widget.routeOptimization.legs;
    majorStops.asMap().forEach((index, step) {
      if (step.address.hasCoordinates) {
        _markers.add(
          Marker(
            markerId: MarkerId('stop_marker_$index'),
            position: LatLng(step.address.latitude!, step.address.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              index == 0 ? BitmapDescriptor.hueViolet : 
              index == 1 ? BitmapDescriptor.hueGreen : 
              BitmapDescriptor.hueRed 
            ),
            infoWindow: InfoWindow(title: step.address.fullAddress, snippet: "Stop ${index + 1}"),
          ),
        );
      }
    });
  }
  
  void _startNavigation() {
    _navigationEngine = NavigationEngine(
      route: widget.routeOptimization,
      isMock: _isEmulator,
      onInstructionChanged: (instruction) {
        if (mounted) setState(() => _currentInstruction = instruction);
      },
      onDistanceChanged: (distance) {
        if (mounted) setState(() => _distanceToNextTurn = distance);
      },
      onPositionUpdated: (position) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 18,
              tilt: 60,
              bearing: position.heading,
            ),
          ),
        );
      },
    );
    _navigationEngine!.start();
  }

  @override
  void dispose() {
    _navigationEngine?.stop();
    _mapController?.dispose();
    super.dispose();
  }
  
  String _formatDistance(double meters) {
    const double metersToFeet = 3.28084;
    const double metersToMiles = 0.000621371;

    if (meters < 402) { // Roughly a quarter mile
      final double feet = meters * metersToFeet;
      final roundedFeet = (feet / 10).round() * 10;
      return "${roundedFeet} feet";
    } else {
      final double miles = meters * metersToMiles;
      return "${miles.toStringAsFixed(1)} miles";
    }
  }

  void _showStepsList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final steps = widget.routeOptimization.detailedSteps;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return ListView.builder(
              controller: scrollController,
              itemCount: steps.length,
              itemBuilder: (context, index) {
                final step = steps[index];
                return ListTile(
                  leading: const Icon(Icons.turn_right_sharp), // Placeholder icon
                  title: Text(step.instructions ?? 'Unknown instruction'),
                  trailing: Text(step.distanceFromPrevious != null 
                      ? _formatDistance(step.distanceFromPrevious! * 1000) // Convert km to meters for formatting
                      : ""),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeSteps = widget.routeOptimization.detailedSteps;
    final initialPos = routeSteps.isNotEmpty ? routeSteps.first.address : widget.routeOptimization.addresses.first;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Navigation"),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: _showStepsList, 
            tooltip: "Show Steps",
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController = controller,
            initialCameraPosition: CameraPosition(
              target: initialPos.hasCoordinates 
                  ? LatLng(initialPos.latitude!, initialPos.longitude!)
                  : const LatLng(40.7143, -73.5994), 
              zoom: 18,
              tilt: 60,
            ),
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: !_isEmulator,
            myLocationButtonEnabled: false,
            buildingsEnabled: true,
            zoomControlsEnabled: false,
          ),
          
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Card(
              margin: const EdgeInsets.all(8),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Next: ${_formatDistance(_distanceToNextTurn)}",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600]
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentInstruction,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _completeDelivery,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text("Complete Delivery"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _completeDelivery() async {
    print('🎉 Completing delivery');
    
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DeliveryInvoiceScreen(
          order: widget.order,
          routeOptimization: widget.routeOptimization,
          actualDuration: const Duration(minutes: 0), 
          startTime: DateTime.now(), 
          endTime: DateTime.now(), 
        ),
      ),
    );

    if (mounted && result == 'completed') {
      Navigator.of(context).pop('completed');
    }
  }
}
