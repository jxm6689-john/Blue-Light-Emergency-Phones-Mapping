import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

void main() {
  runApp(const CampusSafetyApp());
}

// --- GRAPH DATA STRUCTURES ---
class GraphNode {
  final int id;
  final LatLng position;
  bool isPhone = false; // The magic stopping condition
  List<GraphEdge> edges = [];

  GraphNode(this.id, this.position);
}

class GraphEdge {
  final GraphNode target;
  final double distance; // Distance in meters
  GraphEdge(this.target, this.distance);
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
  final MapController _mapController = MapController();
  final Distance _distanceCalc = const Distance();

  // State Variables
  LatLng? userLocation;
  List<LatLng> calculatedPath = [];
  StreamSubscription<Position>? _positionStreamSubscription;

  // UM Campus Bounding Box (Geofence)
  final double minLat = 25.7100;
  final double maxLat = 25.7250;
  final double minLng = -80.2865;
  final double maxLng = -80.2720;
  bool _isUserOnCampus = true;

  // Graph Variables
  bool _isGraphLoaded = false;
  String _loadingStatus = "Initializing...";
  final Map<int, GraphNode> _graph = {};
  List<GraphNode> _graphNodesList = [];

  // Actual Blue-Light Emergency Phones (62 locations)
  final List<LatLng> blueLightPhones = [
    const LatLng(25.7239569, -80.2787170), const LatLng(25.7225994, -80.2793320),
    const LatLng(25.7227966, -80.2786178), const LatLng(25.7219248, -80.2794693),
    const LatLng(25.7228026, -80.2774360), const LatLng(25.7211339, -80.2793878),
    const LatLng(25.7235293, -80.2761860), const LatLng(25.7223033, -80.2772043),
    const LatLng(25.7202817, -80.2796660), const LatLng(25.7222446, -80.2765497),
    const LatLng(25.7188409, -80.2805152), const LatLng(25.7204832, -80.2784307),
    const LatLng(25.7147228, -80.2850056), const LatLng(25.7186163, -80.2800612),
    const LatLng(25.7144760, -80.2849323), const LatLng(25.7216002, -80.2760492),
    const LatLng(25.7220427, -80.2753975), const LatLng(25.7204884, -80.2772902),
    const LatLng(25.7200446, -80.2777429), const LatLng(25.7139409, -80.2853255),
    const LatLng(25.7214990, -80.2755878), const LatLng(25.7144954, -80.2842422),
    const LatLng(25.7141693, -80.2845685), const LatLng(25.7203398, -80.2766842),
    const LatLng(25.7134220, -80.2851825), const LatLng(25.7148320, -80.2832320),
    const LatLng(25.7177018, -80.2794921), const LatLng(25.7194640, -80.2772074),
    const LatLng(25.7126175, -80.2856033), const LatLng(25.7141899, -80.2835557),
    const LatLng(25.7203468, -80.2756959), const LatLng(25.7135267, -80.2841046),
    const LatLng(25.7126257, -80.2851244), const LatLng(25.7122348, -80.2855539),
    const LatLng(25.7168888, -80.2790191), const LatLng(25.7126274, -80.2841700),
    const LatLng(25.7123223, -80.2843690), const LatLng(25.7112351, -80.2854634),
    const LatLng(25.7182019, -80.2767420), const LatLng(25.7179221, -80.2770910),
    const LatLng(25.7183259, -80.2765835), const LatLng(25.7188362, -80.2759101),
    const LatLng(25.7162127, -80.2788985), const LatLng(25.7198349, -80.2742983),
    const LatLng(25.7114826, -80.2843393), const LatLng(25.7176841, -80.2765608),
    const LatLng(25.7119413, -80.2835747), const LatLng(25.7178577, -80.2761374),
    const LatLng(25.7105505, -80.2850572), const LatLng(25.7154882, -80.2783555),
    const LatLng(25.7143119, -80.2797379), const LatLng(25.7190371, -80.2737832),
    const LatLng(25.7108601, -80.2839531), const LatLng(25.7177174, -80.2753716),
    const LatLng(25.7148204, -80.2789179), const LatLng(25.7191173, -80.2734526),
    const LatLng(25.7124412, -80.2817393), const LatLng(25.7129981, -80.2810448),
    const LatLng(25.7195742, -80.2726982), const LatLng(25.7126916, -80.2809121),
    const LatLng(25.7155277, -80.2771854), const LatLng(25.7156548, -80.2762150),
  ];

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
    await _buildCampusGraph();
    await _startLiveLocationTracking();
  }

  // Helper to check geofence boundary
  bool _checkIfOnCampus(LatLng loc) {
    return true; // remove line to enable geofence check

    /*
    return (loc.latitude >= minLat && loc.latitude <= maxLat) &&
        (loc.longitude >= minLng && loc.longitude <= maxLng);
     */
  }

  // --- 1. BUILD THE GRAPH ---
  Future<void> _buildCampusGraph() async {
    setState(() => _loadingStatus = "Downloading Campus Pathways...");

    // Bounding Box roughly around UM Coral Gables
    final String query = '''
      [out:json];
      (
        way["highway"~"footway|path|pedestrian"]($minLat,$minLng,$maxLat,$maxLng);
      );
      (._;>;);
      out body;
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
      );

      if (response.statusCode == 200) {
        setState(() => _loadingStatus = "Building Navigation Network...");
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        // Extract raw nodes
        for (var el in elements) {
          if (el['type'] == 'node') {
            int id = el['id'];
            _graph[id] = GraphNode(id, LatLng(el['lat'], el['lon']));
          }
        }

        // Connect the edges
        for (var el in elements) {
          if (el['type'] == 'way') {
            List<dynamic> nodeIds = el['nodes'];
            for (int i = 0; i < nodeIds.length - 1; i++) {
              GraphNode? n1 = _graph[nodeIds[i]];
              GraphNode? n2 = _graph[nodeIds[i + 1]];

              if (n1 != null && n2 != null) {
                double dist = _distanceCalc(n1.position, n2.position);
                n1.edges.add(GraphEdge(n2, dist));
                n2.edges.add(GraphEdge(n1, dist));
              }
            }
          }
        }

        _graphNodesList = _graph.values.toList();

        // Snap the 62 phones to the graph
        setState(() => _loadingStatus = "Mapping Emergency Phones...");
        for (LatLng phoneLoc in blueLightPhones) {
          GraphNode nearestNode = _findNearestNode(phoneLoc);
          nearestNode.isPhone = true;
        }

        setState(() {
          _isGraphLoaded = true;
          _loadingStatus = "Ready";
        });

        // Run route if GPS is already locked and user is on campus
        if (userLocation != null && _isUserOnCampus) _calculatePathToNearestPhone();

      }
    } catch (e) {
      setState(() => _loadingStatus = "Failed to load graph. Ensure internet connection.");
    }
  }

  // Snaps arbitrary coordinates to the physical graph
  GraphNode _findNearestNode(LatLng target) {
    GraphNode nearest = _graphNodesList.first;
    double minDist = double.infinity;

    for (var node in _graphNodesList) {
      double dist = _distanceCalc(target, node.position);
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }
    return nearest;
  }

// --- 2. GPS TRACKING & GEOFENCING ---
  Future<void> _startLiveLocationTracking() async {
    try {
      setState(() => _loadingStatus = "Acquiring GPS Signal...");

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _loadingStatus = "Error: Location services are disabled. Please turn on GPS.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _loadingStatus = "Error: Location permission denied.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _loadingStatus = "Error: Location permissions are permanently denied. Please enable in settings.");
        return;
      }

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((Position? position) {
        if (position != null && mounted) {
          LatLng newLoc = LatLng(position.latitude, position.longitude);
          bool onCampus = _checkIfOnCampus(newLoc);

          setState(() {
            userLocation = newLoc;
            _isUserOnCampus = onCampus;

            // Only calculate if they are on campus and map is ready
            if (_isUserOnCampus && _isGraphLoaded) {
              _calculatePathToNearestPhone();
            }
          });
        }
      });
    } catch (e) {
      // Catches MissingPluginException or permission definition errors
      setState(() => _loadingStatus = "System Error: \n$e");
    }
  }
  // --- 3. DIJKSTRA'S ALGORITHM ---
  // Temporary memory for Dijkstra algorithm
  final Map<int, double> _distances = {};
  final Map<int, GraphNode> _previous = {};

  void _calculatePathToNearestPhone() {
    if (userLocation == null || !_isGraphLoaded) return;

    GraphNode startNode = _findNearestNode(userLocation!);

    PriorityQueue<GraphNode> queue = PriorityQueue((a, b) =>
        (_distances[a.id] ?? double.infinity).compareTo(_distances[b.id] ?? double.infinity)
    );

    _distances.clear();
    _previous.clear();
    Set<int> visited = {};

    _distances[startNode.id] = 0;
    queue.add(startNode);

    GraphNode? targetPhoneNode;

    while (queue.isNotEmpty) {
      GraphNode current = queue.removeFirst();

      // Stop immediately upon hitting ANY phone
      if (current.isPhone) {
        targetPhoneNode = current;
        break;
      }

      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (GraphEdge edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        double newDist = _distances[current.id]! + edge.distance;

        if (newDist < (_distances[edge.target.id] ?? double.infinity)) {
          _distances[edge.target.id] = newDist;
          _previous[edge.target.id] = current;
          queue.add(edge.target);
        }
      }
    }

    // Trace the path backwards and update the UI
    if (targetPhoneNode != null) {
      List<LatLng> path = [];
      GraphNode? curr = targetPhoneNode;
      while (curr != null) {
        path.add(curr.position);
        curr = _previous[curr.id];
      }

      setState(() {
        calculatedPath = path.reversed.toList();
      });
    }
  }

  void _recenterMap() {
    if (userLocation != null) _mapController.move(userLocation!, 16.5);
  }

  // --- UI RENDERING ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _recenterMap,
        backgroundColor: Colors.blue[900],
        child: const Icon(Icons.location_searching, color: Colors.white),
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
            Text(_loadingStatus),
          ],
        ),
      )
      // State 3: Normal Functionality
          : FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(25.7239569, -80.2787170), //userLocation!,
          initialZoom: 16.5,
          initialRotation: 42.0,
          minZoom: 16.5,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.campus-safety',
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
              Marker(
                point: userLocation!,
                width: 40, height: 40,
                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
              ),
              ...blueLightPhones.map(
                    (phoneLoc) => Marker(
                      width: 40,
                      height: 40,
                      rotate: true,
                  point: phoneLoc,
                  child: Card(
                      margin: EdgeInsets.zero,
                      shape: CircleBorder(),
                      elevation: 5,
                      color: Colors.white,
                      child: Center(child: Icon(Icons.location_on, color: Colors.blueAccent, size: 30, fill: 1.0))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}