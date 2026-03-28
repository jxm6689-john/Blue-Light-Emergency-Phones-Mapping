import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';

void main() {
  runApp(const CampusSafetyApp());
}

class CampusSafetyApp extends StatelessWidget {
  const CampusSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UM Campus Safety Route',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CampusMapScreen(),
    );
  }
}

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  // Center of University of Miami Campus
  final LatLng umCenter = const LatLng(25.7173, -80.2781);

  // Mock User Location (Slightly offset from center)
  final LatLng userLocation = const LatLng(25.7185, -80.2790);

  List<LatLng> blueLightPhones = [];
  List<LatLng> jaggedPath = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _generateRandomPhones();
    _generateJaggedPath();
  }

  // Generates 5 random locations around the campus center
  void _generateRandomPhones() {
    for (int i = 0; i < 5; i++) {
      // Create a small random offset for latitude and longitude
      double latOffset = (_random.nextDouble() - 0.5) * 0.01;
      double lngOffset = (_random.nextDouble() - 0.5) * 0.01;
      blueLightPhones.add(
          LatLng(umCenter.latitude + latOffset, umCenter.longitude + lngOffset)
      );
    }
  }

  // Simulates a non-straight walking path to the first random phone
  void _generateJaggedPath() {
    LatLng targetPhone = blueLightPhones.first;

    // Create random intermediate waypoints to make the line jagged
    LatLng waypoint1 = LatLng(
      (userLocation.latitude + targetPhone.latitude) / 2 + 0.001,
      (userLocation.longitude + targetPhone.longitude) / 2 - 0.002,
    );
    LatLng waypoint2 = LatLng(
      (userLocation.latitude + targetPhone.latitude) / 2 - 0.0015,
      (userLocation.longitude + targetPhone.longitude) / 2 + 0.001,
    );

    // Build the path sequence
    jaggedPath = [userLocation, waypoint1, waypoint2, targetPhone];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Route Prototype'),
        backgroundColor: Colors.blue[900],
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: umCenter,
          initialZoom: 15.5,
        ),
        children: [
          // 1. The OpenStreetMap Tile Layer
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.campussafety',
          ),

          // 2. The Jagged Path Layer
          PolylineLayer(
            polylines: [
              Polyline(
                points: jaggedPath,
                color: Colors.green, // Green to signify a "Safe Route"
                strokeWidth: 4.0,
              ),
            ],
          ),

          // 3. The Markers Layer (User + 5 Phones)
          MarkerLayer(
            markers: [
              // User Marker (Red Pin)
              Marker(
                point: userLocation,
                width: 40,
                height: 40,
                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
              ),
              // Blue Light Phone Markers (Generated List)
              ...blueLightPhones.map(
                    (phoneLoc) => Marker(
                  point: phoneLoc,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.emergency_share, color: Colors.blue, size: 30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}