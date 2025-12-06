import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class DriverMarker {
  static BitmapDescriptor? _driverIcon;

  static Future<void> loadCustomMarker() async {
    // In a real app, you might load a custom image:
    // _driverIcon = await BitmapDescriptor.fromAssetImage(
    //   const ImageConfiguration(size: Size(48, 48)),
    //   'assets/driver_icon.png', 
    // );
    // For now, we'll use a default marker.
    _driverIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
  }

  static Marker getMarker(LocationData location) {
    return Marker(
      markerId: const MarkerId('driver_location'),
      position: LatLng(location.latitude!, location.longitude!),
      icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
      rotation: location.heading ?? 0.0,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 2,
    );
  }

  static Set<Circle> getPulseCircles(AnimationController controller, LocationData location) {
    final Color pulseColor = Colors.blue.withOpacity(0.5);
    
    final pulseAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOut,
      ),
    );

    return {
      Circle(
        circleId: const CircleId('pulse'),
        center: LatLng(location.latitude!, location.longitude!),
        radius: 50 * pulseAnimation.value,
        fillColor: pulseColor.withOpacity(0.3 - (0.3 * pulseAnimation.value)),
        strokeColor: pulseColor.withOpacity(0.5 - (0.5 * pulseAnimation.value)),
        strokeWidth: 1,
        zIndex: 1,
      ),
    };
  }
}
