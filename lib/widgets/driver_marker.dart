
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class DriverMarker {
  static BitmapDescriptor? _customMarkerIcon;

  static Future<void> loadCustomMarker() async {
    if (_customMarkerIcon != null) return;
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(40, 40)),
        'assets/icons/tringle-icon.png',
      );
      _customMarkerIcon = icon;
    } catch (e) {
      print('Error loading custom marker icon: $e');
      _customMarkerIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  static Marker getMarker(LocationData locationData) {
    return Marker(
      markerId: const MarkerId('driver_location'),
      position: LatLng(locationData.latitude!, locationData.longitude!),
      icon: _customMarkerIcon!,
      rotation: locationData.heading ?? 0.0,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      infoWindow: const InfoWindow(title: 'You are here'),
    );
  }

  static Set<Circle> getPulseCircles(
      AnimationController pulseController, LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) {
      return {};
    }

    final double baseRadius = 20.0;
    final double maxRadius = 150.0;

    final double progress1 = pulseController.value;
    final double radius1 = baseRadius + (maxRadius - baseRadius) * progress1;
    final double opacity1 = (1.0 - progress1) * 0.6;

    final double progress2 = (pulseController.value + 0.5) % 1.0;
    final double radius2 = baseRadius + (maxRadius - baseRadius) * progress2;
    final double opacity2 = (1.0 - progress2) * 0.6;

    final circle1 = Circle(
      circleId: const CircleId('pulse_circle_1'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: radius1,
      fillColor: Colors.greenAccent.withOpacity(opacity1),
      strokeColor: Colors.greenAccent.withOpacity(opacity1 * 0.5),
      strokeWidth: 1,
    );

    final circle2 = Circle(
      circleId: const CircleId('pulse_circle_2'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: radius2,
      fillColor: Colors.greenAccent.withOpacity(opacity2),
      strokeColor: Colors.greenAccent.withOpacity(opacity2 * 0.5),
      strokeWidth: 1,
    );

    final coreCircle = Circle(
      circleId: const CircleId('core_circle'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: 30.0,
      fillColor: Colors.green.withOpacity(0.5),
      strokeColor: Colors.white.withOpacity(0.8),
      strokeWidth: 2,
    );

    return {circle1, circle2, coreCircle};
  }
}
