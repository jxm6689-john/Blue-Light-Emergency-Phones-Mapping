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

  bool _isSatelliteMode = false;

  // State for Custom Destination Routing
  bool _isDestinationMode = false;
  LatLng? destinationLocation;

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

      await _startLiveLocationTracking();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStatus = e.toString());
      }
    }
  }

  void _calculateActiveRoute() {
    if (userLocation == null || !_isUserOnCampus || !_isGraphLoaded) return;

    List<LatLng>? path;
    if (_isDestinationMode && destinationLocation != null) {
      path = _routingService.calculatePathToDestination(userLocation!, destinationLocation!, _graphNodesList);
    } else {
      path = _routingService.calculatePathToNearestPhone(userLocation!, _graphNodesList);
    }

    // Clear cached polylines when route changes
    setState(() {
      calculatedPath = path ?? [];
      _cachedPolylines = null;
      _cachedRoutePoints = null;
    });
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
            _calculateActiveRoute(); // Trigger recalculation
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

  // --- OPTIMIZED POLYLINE RENDERING ---

  /// Cached polylines to avoid recalculating on every rebuild
  List<Polyline>? _cachedPolylines;
  List<LatLng>? _cachedRoutePoints;

  // Define the bounding box for the specific section
  final LatLngBounds specialSectionBounds = LatLngBounds(
    const LatLng(25.714585572558533, -80.285733794313),
    const LatLng(25.711808623312717, -80.28326643625026),
  );

  bool _isInSpecialSection(LatLng point) {
    return specialSectionBounds.contains(point);
  }

  double _getPlaceholderLightLevel(LatLng point) {
    return 0.5;
  }

  Color _getSegmentColor(LatLng point) {
    if (_isInSpecialSection(point)) {
      final lightLevel = _getPlaceholderLightLevel(point);
      return Color.lerp(Colors.yellow, Colors.red, lightLevel) ?? Colors.yellow;
    }
    return _isDestinationMode ? Colors.green : Colors.blue;
  }

  /// Optimized polyline generation with caching and batching
  List<Polyline> _generateRoutedPolylines(List<LatLng> routePoints) {
    if (routePoints.isEmpty || routePoints.length < 2) return [];

    // Return cached result if route hasn't changed
    if (_cachedPolylines != null && 
        _cachedRoutePoints != null &&
        listEquals(_cachedRoutePoints, routePoints)) {
      return _cachedPolylines!;
    }

    final polylines = <Polyline>[];
    
    // Batch points by color to minimize Polyline objects
    var currentBatchPoints = <LatLng>[routePoints[0]];
    var currentBatchColor = _getSegmentColor(routePoints[0]);

    for (int i = 0; i < routePoints.length - 1; i++) {
      final nextPoint = routePoints[i + 1];
      final nextPointColor = _getSegmentColor(nextPoint);

      if (nextPointColor == currentBatchColor) {
        currentBatchPoints.add(nextPoint);
      } else {
        currentBatchPoints.add(nextPoint);
        polylines.add(_createPolyline(currentBatchPoints, currentBatchColor));
        currentBatchPoints = [nextPoint];
        currentBatchColor = nextPointColor;
      }
    }

    if (currentBatchPoints.length > 1) {
      polylines.add(_createPolyline(currentBatchPoints, currentBatchColor));
    }

    // Cache the result
    _cachedPolylines = polylines;
    _cachedRoutePoints = routePoints;

    return polylines;
  }

  Polyline _createPolyline(List<LatLng> points, Color color) {
    return Polyline(
      points: points,
      color: color,
      strokeWidth: 5.0,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    );
  }

  // NEW: Helper method to show the confirmation dialog
  void _showRouteConfirmationDialog(LatLng point) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Destination'),
          content: const Text('Would you like to route through the blue light network to this location?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
                setState(() {
                  destinationLocation = point;
                  _calculateActiveRoute(); // Trigger the route generation
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Route', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
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
              setState(() {
                _isDestinationMode = !_isDestinationMode;
                if (!_isDestinationMode) {
                  destinationLocation = null; // Clear destination when disabled
                }
                _calculateActiveRoute(); // Recalculate based on new mode
              });
            },
            backgroundColor: _isDestinationMode ? Colors.green : Colors.blue[900],
            child: Icon(
                _isDestinationMode ? Icons.directions_walk : Icons.emergency,
                color: Colors.white,
                size: 27
            ),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: () {
              setState(() {
                _isSatelliteMode = !_isSatelliteMode;
              });
            },
            backgroundColor: Colors.blue[900],
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
          : FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: userLocation!,
          initialZoom: 16.5,
          initialRotation: 42.0,
          minZoom: 16.5,
          maxZoom: 23,
          // CHANGED: Replaced onTap with onLongPress and integrated the dialog
          onLongPress: (tapPosition, point) {
            if (_isDestinationMode && _isGraphLoaded) {
              _showRouteConfirmationDialog(point);
            }
          },
          onTap: (tapPosition, point) {
            print('📍 Map clicked at: Latitude: ${point.latitude}, Longitude: ${point.longitude}');
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.campus-safety',
          ),
          AnimatedOpacity(
            opacity: _isSatelliteMode ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: Colors.grey.shade400,
            ),
          ),
          AnimatedOpacity(
            opacity: _isSatelliteMode ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: TileLayer(
              urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.example.campus-safety',
            ),
          ),
          PolylineLayer(
            // Replace the single blue polyline with the segmented, color-coded ones
            polylines: _generateRoutedPolylines(calculatedPath),
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
              ),

              if (destinationLocation != null && _isDestinationMode)
                Marker(
                  point: destinationLocation!,
                  width: 40,
                  height: 40,
                  child: const Card(
                      margin: EdgeInsets.zero,
                      shape: CircleBorder(),
                      elevation: 5,
                      color: Colors.white,
                      child: Center(
                          child: Icon(Icons.flag_circle, color: Colors.green, size: 38),
                      )
                  ),
                ),

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