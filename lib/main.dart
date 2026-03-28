import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

void main() {
  runApp(const CampusSafetyApp());
}

class CampusSafetyApp extends StatelessWidget {
  const CampusSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UM Campus Safety Route',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const CampusMapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  // Center of University of Miami Campus (Fallback)
  final LatLng umCenter = const LatLng(25.7173, -80.2781);

  // Map Controller to programmatically move the camera
  final MapController _mapController = MapController();

  // State Variables
  LatLng? userLocation;
  List<LatLng> calculatedPath = [];
  StreamSubscription<Position>? _positionStreamSubscription;

  // Actual Blue-Light Emergency Phones (62 locations)
  final List<LatLng> blueLightPhones = [
    const LatLng(25.7239569, -80.2787170), // Phone 1
    const LatLng(25.7225994, -80.2793320), // Phone 2
    const LatLng(25.7227966, -80.2786178), // Phone 3
    const LatLng(25.7219248, -80.2794693), // Phone 4
    const LatLng(25.7228026, -80.2774360), // Phone 5
    const LatLng(25.7211339, -80.2793878), // Phone 6
    const LatLng(25.7235293, -80.2761860), // Phone 7
    const LatLng(25.7223033, -80.2772043), // Phone 8
    const LatLng(25.7202817, -80.2796660), // Phone 9
    const LatLng(25.7222446, -80.2765497), // Phone 10
    const LatLng(25.7188409, -80.2805152), // Phone 11
    const LatLng(25.7204832, -80.2784307), // Phone 12
    const LatLng(25.7147228, -80.2850056), // Phone 13
    const LatLng(25.7186163, -80.2800612), // Phone 14
    const LatLng(25.7144760, -80.2849323), // Phone 15
    const LatLng(25.7216002, -80.2760492), // Phone 16
    const LatLng(25.7220427, -80.2753975), // Phone 17
    const LatLng(25.7204884, -80.2772902), // Phone 18
    const LatLng(25.7200446, -80.2777429), // Phone 19
    const LatLng(25.7139409, -80.2853255), // Phone 20
    const LatLng(25.7214990, -80.2755878), // Phone 21
    const LatLng(25.7144954, -80.2842422), // Phone 22
    const LatLng(25.7141693, -80.2845685), // Phone 23
    const LatLng(25.7203398, -80.2766842), // Phone 24
    const LatLng(25.7134220, -80.2851825), // Phone 25
    const LatLng(25.7148320, -80.2832320), // Phone 26
    const LatLng(25.7177018, -80.2794921), // Phone 27
    const LatLng(25.7194640, -80.2772074), // Phone 28
    const LatLng(25.7126175, -80.2856033), // Phone 29
    const LatLng(25.7141899, -80.2835557), // Phone 30
    const LatLng(25.7203468, -80.2756959), // Phone 31
    const LatLng(25.7135267, -80.2841046), // Phone 32
    const LatLng(25.7126257, -80.2851244), // Phone 33
    const LatLng(25.7122348, -80.2855539), // Phone 34
    const LatLng(25.7168888, -80.2790191), // Phone 35
    const LatLng(25.7126274, -80.2841700), // Phone 36
    const LatLng(25.7123223, -80.2843690), // Phone 37
    const LatLng(25.7112351, -80.2854634), // Phone 38
    const LatLng(25.7182019, -80.2767420), // Phone 39
    const LatLng(25.7179221, -80.2770910), // Phone 40
    const LatLng(25.7183259, -80.2765835), // Phone 41
    const LatLng(25.7188362, -80.2759101), // Phone 42
    const LatLng(25.7162127, -80.2788985), // Phone 43
    const LatLng(25.7198349, -80.2742983), // Phone 44
    const LatLng(25.7114826, -80.2843393), // Phone 45
    const LatLng(25.7176841, -80.2765608), // Phone 46
    const LatLng(25.7119413, -80.2835747), // Phone 47
    const LatLng(25.7178577, -80.2761374), // Phone 48
    const LatLng(25.7105505, -80.2850572), // Phone 49
    const LatLng(25.7154882, -80.2783555), // Phone 50
    const LatLng(25.7143119, -80.2797379), // Phone 51
    const LatLng(25.7190371, -80.2737832), // Phone 52
    const LatLng(25.7108601, -80.2839531), // Phone 53
    const LatLng(25.7177174, -80.2753716), // Phone 54
    const LatLng(25.7148204, -80.2789179), // Phone 55
    const LatLng(25.7191173, -80.2734526), // Phone 56
    const LatLng(25.7124412, -80.2817393), // Phone 57
    const LatLng(25.7129981, -80.2810448), // Phone 58
    const LatLng(25.7195742, -80.2726982), // Phone 59
    const LatLng(25.7126916, -80.2809121), // Phone 60
    const LatLng(25.7155277, -80.2771854), // Phone 61
    const LatLng(25.7156548, -80.2762150), // Phone 62
  ];

  @override
  void initState() {
    super.initState();
    _startLiveLocationTracking();
  }

  @override
  void dispose() {
    // Prevent memory leaks and save battery by cancelling the GPS stream when closed
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // Requests permission and continuously listens to live GPS data
  Future<void> _startLiveLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    // 2. Request Permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    // 3. Configure tracking frequency (updates when user moves 5 meters)
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    // 4. Listen to the live stream
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position? position) {
      if (position != null && mounted) {
        setState(() {
          // Update the user's live location
          userLocation = LatLng(position.latitude, position.longitude);

          // Recalculate the route dynamically based on the new location
          _calculatePathToNearestPhone();
        });
      }
    });
  }

  // Finds the closest phone mathematically and draws a direct line
  void _calculatePathToNearestPhone() {
    if (userLocation == null || blueLightPhones.isEmpty) return;

    const distanceCalculator = Distance();
    LatLng nearestPhone = blueLightPhones.first;
    double minDistance = distanceCalculator(userLocation!, nearestPhone);

    // Loop through all 62 to find the shortest physical distance
    for (var phone in blueLightPhones) {
      double dist = distanceCalculator(userLocation!, phone);
      if (dist < minDistance) {
        minDistance = dist;
        nearestPhone = phone;
      }
    }

    // Update the visual path to point directly to the new nearest phone
    calculatedPath = [userLocation!, nearestPhone];
  }

  // Helper method to recenter the map on the user if they pan away
  void _recenterMap() {
    if (userLocation != null) {
      _mapController.move(userLocation!, 16.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Route Prototype', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue[900],
      ),
      // Floating Action Button to let the user recenter the map on themselves
      floatingActionButton: FloatingActionButton(
        onPressed: _recenterMap,
        backgroundColor: Colors.blue[900],
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
      // Show a loading indicator until the GPS secures the initial lock
      body: userLocation == null
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Acquiring GPS Signal..."),
          ],
        ),
      )
          : FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: userLocation!,
          initialZoom: 16.5,
        ),
        children: [
          // 1. The OpenStreetMap Tile Layer (Optimized for performance)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.campussafety',
            tileProvider: CancellableNetworkTileProvider(),
          ),

          // 2. The Direct Path Layer (Dynamic green line)
          PolylineLayer(
            polylines: [
              Polyline(
                points: calculatedPath,
                color: Colors.green,
                strokeWidth: 4.0,
              ),
            ],
          ),

          // 3. The Markers Layer
          MarkerLayer(
            markers: [
              // User Marker (Red Pin at Live Location)
              Marker(
                point: userLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
              ),
              // Blue Light Phone Markers
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