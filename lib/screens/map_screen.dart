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
  
  // Route statistics
  double? _totalDistance;
  int? _estimatedTime;
  int? _phonesOnRoute;
  
  // Color cache for consistent segment colors
  final Map<String, Color> _colorCache = {};

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
        setState(() => _loadingStatus = "Error: $e");
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

    if (mounted) {
      setState(() {
        calculatedPath = path ?? [];
        _updateRouteStatistics();
      });
    }
  }
  
  void _updateRouteStatistics() {
    if (calculatedPath.isEmpty) {
      _totalDistance = null;
      _estimatedTime = null;
      _phonesOnRoute = null;
      return;
    }
    
    // Calculate total distance
    double total = 0;
    for (int i = 0; i < calculatedPath.length - 1; i++) {
      total += const Distance()(calculatedPath[i], calculatedPath[i + 1]);
    }
    _totalDistance = total;
    _estimatedTime = (total / 83.3).ceil(); // ~5 km/h walking speed
    
    // Count phones on route (simplified: check proximity)
    int phoneCount = 0;
    for (var phone in blueLightPhones) {
      for (var point in calculatedPath) {
        if (const Distance()(phone, point) < 20) {
          phoneCount++;
          break;
        }
      }
    }
    _phonesOnRoute = phoneCount;
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
            _calculateActiveRoute();
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

  // --- LIGHT LEVEL & GRADIENT LOGIC ---

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
      double lightLevel = _getPlaceholderLightLevel(point);
      // Use rounded light level as cache key for consistent colors
      String cacheKey = lightLevel.toStringAsFixed(2);
      return _colorCache.putIfAbsent(
        cacheKey, 
        () => Color.lerp(Colors.yellow, Colors.red, lightLevel) ?? Colors.yellow
      );
    }
    return _isDestinationMode ? Colors.green : Colors.blue;
  }
  
  // Smooth path using Catmull-Rom interpolation
  List<LatLng> _smoothPath(List<LatLng> originalPath) {
    if (originalPath.length < 3) return originalPath;
    
    List<LatLng> smoothed = [originalPath.first];
    for (int i = 1; i < originalPath.length - 1; i++) {
      final prev = originalPath[i - 1];
      final curr = originalPath[i];
      final next = originalPath[i + 1];
      
      smoothed.add(LatLng(
        (prev.latitude + curr.latitude * 2 + next.latitude) / 4,
        (prev.longitude + curr.longitude * 2 + next.longitude) / 4,
      ));
    }
    smoothed.add(originalPath.last);
    return smoothed;
  }

  List<Polyline> _generateRoutedPolylines(List<LatLng> routePoints) {
    if (routePoints.isEmpty || routePoints.length < 2) return [];
    
    // Apply path smoothing
    final smoothedPoints = _smoothPath(routePoints);

    List<Polyline> polylines = [];
    List<LatLng> currentBatchPoints = [smoothedPoints[0]];
    Color currentBatchColor = _getSegmentColor(smoothedPoints[0]);

    for (int i = 0; i < smoothedPoints.length - 1; i++) {
      LatLng nextPoint = smoothedPoints[i + 1];
      Color nextPointColor = _getSegmentColor(nextPoint);

      if (nextPointColor == currentBatchColor) {
        currentBatchPoints.add(nextPoint);
      } else {
        currentBatchPoints.add(nextPoint);
        polylines.add(
          Polyline(
            points: List.from(currentBatchPoints),
            color: currentBatchColor,
            strokeWidth: 5.0,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );

        currentBatchPoints = [nextPoint];
        currentBatchColor = nextPointColor;
      }
    }

    if (currentBatchPoints.length > 1) {
      polylines.add(
        Polyline(
          points: currentBatchPoints,
          color: currentBatchColor,
          strokeWidth: 5.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      );
    }

    return polylines;
  }
  
  // Detect significant turns for turn-by-turn indicators
  List<_TurnInfo> _detectSignificantTurns(List<LatLng> routePoints) {
    List<_TurnInfo> turns = [];
    if (routePoints.length < 3) return turns;
    
    for (int i = 1; i < routePoints.length - 1; i++) {
      final prev = routePoints[i - 1];
      final curr = routePoints[i];
      final next = routePoints[i + 1];
      
      // Calculate bearing change
      final bearing1 = _calculateBearing(prev, curr);
      final bearing2 = _calculateBearing(curr, next);
      double angleChange = (bearing2 - bearing1).abs();
      if (angleChange > 180) angleChange = 360 - angleChange;
      
      // Only mark significant turns (>45 degrees)
      if (angleChange > 45) {
        final direction = bearing2 > bearing1 ? 1 : -1;
        turns.add(_TurnInfo(location: curr, direction: direction, angle: angleChange));
      }
    }
    return turns;
  }
  
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * 3.14159 / 180;
    final lat2 = to.latitude * 3.14159 / 180;
    final dLon = (to.longitude - from.longitude) * 3.14159 / 180;
    
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final brng = atan2(y, x);
    
    return (brng * 180 / 3.14159 + 360) % 360;
  }

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
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  destinationLocation = point;
                  _calculateActiveRoute();
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
                  destinationLocation = null;
                }
                _calculateActiveRoute();
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

      body: Stack(
        children: [
          !_isUserOnCampus
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
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _loadingStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_loadingStatus.contains("Downloading"))
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
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
              // Improved satellite mode transition with cross-fade
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _isSatelliteMode ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_isSatelliteMode,
                    child: TileLayer(
                      urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.example.campus-safety',
                    ),
                  ),
                ),
              ),
              PolylineLayer(
                polylines: _generateRoutedPolylines(calculatedPath),
              ),
              // Turn indicators
              if (calculatedPath.length > 2)
                ..._detectSignificantTurns(calculatedPath).map((turn) => MarkerLayer(
                  markers: [
                    Marker(
                      point: turn.location,
                      width: 40,
                      height: 40,
                      child: Icon(
                        turn.direction > 0 ? Icons.turn_right : Icons.turn_left,
                        color: Colors.orange,
                        size: 32,
                      ),
                    ),
                  ],
                )),
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
          
          // Route information panel
          if (_isGraphLoaded && calculatedPath.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _InfoChip(
                        icon: Icons.directions_walk,
                        label: _totalDistance != null 
                            ? '${(_totalDistance! / 1000).toStringAsFixed(2)} km'
                            : '-',
                      ),
                      _InfoChip(
                        icon: Icons.access_time,
                        label: _estimatedTime != null 
                            ? '$_estimatedTime min'
                            : '-',
                      ),
                      _InfoChip(
                        icon: Icons.emergency,
                        label: _phonesOnRoute?.toString() ?? '-',
                        tooltip: 'Phones on route',
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TurnInfo {
  final LatLng location;
  final int direction; // 1 for right, -1 for left
  final double angle;
  
  _TurnInfo({required this.location, required this.direction, required this.angle});
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  
  const _InfoChip({required this.icon, required this.label, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.blue[900]),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}