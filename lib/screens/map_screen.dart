import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

// Import refactored models and services
import '../locations.dart';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';
import '../services/map_service.dart';
import '../services/routing_service.dart';
import 'package:blue_light_emergency_phones_mapping/services/location_service.dart';

class CampusMapScreen extends StatefulWidget {
  const CampusMapScreen({super.key});

  @override
  State<CampusMapScreen> createState() => _CampusMapScreenState();
}

class _CampusMapScreenState extends State<CampusMapScreen> {
  final MapController _mapController = MapController();

  // Services
  final MapService _mapService = MapService();
  final RoutingService _routingService = RoutingService();
  final LocationService _locationService = LocationService();

  // State Variables
  LatLng? userLocation;
  List<LatLng> calculatedPath = [];
  StreamSubscription<Position>? _positionStreamSubscription;

  bool _isUserOnCampus = true;
  bool _isGraphLoaded = false;
  String _loadingStatus = "Initializing...";
  List<GraphNode> _graphNodesList = [];

  // Added state for tracking map/satellite mode
  bool _isSatelliteMode = false;

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeSystem() async {
    try {
      // 1. Fetch the Overpass API data and build the graph
      _graphNodesList = await _mapService.fetchAndBuildGraph((status) {
        if (mounted) {
          setState(() => _loadingStatus = status);
        }
      });

      if (mounted) {
        setState(() {
          _isGraphLoaded = true;
          _loadingStatus = "Ready";
        });
      }

      // 2. Start asking for GPS permissions and stream location
      await _startLiveLocationTracking();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStatus = e.toString());
      }
    }
  }

  Future<void> _startLiveLocationTracking() async {
    try {
      if (mounted) {
        setState(() => _loadingStatus = "Acquiring GPS Signal...");
      }

      await _locationService.requestPermissions();

      _positionStreamSubscription = _locationService.getPositionStream().listen((Position? position) {
        if (position != null && mounted) {
          LatLng newLoc = LatLng(position.latitude, position.longitude);

          setState(() {
            userLocation = newLoc;
            _isUserOnCampus = _mapService.checkIfOnCampus(newLoc);

            // Calculate new path when position updates, if everything is ready
            if (_isUserOnCampus && _isGraphLoaded) {
              final path = _routingService.calculatePathToNearestPhone(newLoc, _graphNodesList);
              if (path != null) {
                calculatedPath = path;
              }
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStatus = "System Error: \n$e");
      }
    }
  }

  void _recenterMap() {
    if (userLocation != null) _mapController.move(userLocation!, 16.5);
  }

  // --- UI RENDERING ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              // Toggle satellite mode
              setState(() {
                _isSatelliteMode = !_isSatelliteMode;
              });
            },
            backgroundColor: Colors.blue[900],
            // Switch icons based on current mode
            child: Icon(
                _isSatelliteMode ? Icons.map_sharp : Icons.satellite_alt_sharp,
                color: Colors.white,
                size: 27
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: _recenterMap,
            backgroundColor: Colors.blue[900],
            child: const Icon(Icons.my_location_sharp, color: Colors.white, size: 27),
          ),
        ],
      ),

      // State 1: Off Campus (Geofence triggered)
      body: !_isUserOnCampus
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "You are currently off-campus.",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                "The safety routing network is only available within the University of Miami Coral Gables boundaries.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        ),
      )

      // State 2: Loading Map/GPS data
          : (!_isGraphLoaded || userLocation == null)
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _loadingStatus,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )

      // State 3: Normal Functionality
          : FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(25.7239569, -80.2787170), // UM Campus center
          initialZoom: 16.5,
          initialRotation: 42.0,
          minZoom: 16.5,
        ),
        children: [
          // BASE LAYER: Normal Street Map (Always loading in the background)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.campus-safety',
          ),

          // TOP LAYER: Satellite Map (Loads simultaneously, opacity controls visibility)
          AnimatedOpacity(
            opacity: _isSatelliteMode ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300), // Smooth fade transition
            child: TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.example.campus-safety',
            ),
          ),

          PolylineLayer(
            polylines: [
              Polyline(
                points: calculatedPath,
                color: Colors.green,
                strokeWidth: 5.0,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              // User location marker
              Marker(
                point: userLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
              ),

              // Blue light phones markers
              ...blueLightPhones.map(
                    (phoneLoc) => Marker(
                  width: 40,
                  height: 40,
                  rotate: true,
                  point: phoneLoc,
                  child: const Card(
                      margin: EdgeInsets.zero,
                      shape: CircleBorder(),
                      elevation: 5,
                      color: Colors.white,
                      child: Center(
                          child: Icon(Icons.location_on, color: Colors.blueAccent, size: 30, fill: 1.0)
                      )
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}