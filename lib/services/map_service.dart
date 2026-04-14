import 'dart:convert';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../locations.dart';
import 'routing_service.dart';

class MapService {
  // UM Campus Bounding Box (Geofence)
  static const double minLat = 25.7100;
  static const double maxLat = 25.7250;
  static const double minLng = -80.2865;
  static const double maxLng = -80.2720;
  final Distance _distanceCalc = const Distance();
  
  // Graph caching to avoid redundant downloads
  List<GraphNode>? _cachedGraph;
  DateTime? _cacheTimestamp;
  static const Duration _cacheDuration = Duration(hours: 24);

  Future<List<GraphNode>> fetchAndBuildGraph(Function(String) onStatusUpdate) async {
    // Return cached graph if available and not expired
    if (_cachedGraph != null && 
        _cacheTimestamp != null && 
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      onStatusUpdate("Using cached navigation network...");
      return _cachedGraph!;
    }
    
    onStatusUpdate("Downloading Campus Pathways...");

    // Added timeout and maxsize parameters for better reliability
    final String query = '''
      [out:json][timeout:25][maxsize:104857600];
      (
          way["highway"~"footway|path|pedestrian"]["area"!~"yes"]($minLat,$minLng,$maxLat,$maxLng);
      );
      (._;>;);
      out body;
    ''';

    final response = await http.post(
      Uri.parse('https://overpass-api.de/api/interpreter'),
      body: query,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to load graph. Ensure internet connection.");
    }

    onStatusUpdate("Building Navigation Network...");
    final data = json.decode(response.body);
    final elements = data['elements'] as List;

    Map<int, GraphNode> graphMap = {};

    for (var el in elements) {
      if (el['type'] == 'node') {
        int id = el['id'];
        graphMap[id] = GraphNode(id, LatLng(el['lat'], el['lon']));
      }
    }

    for (var el in elements) {
      if (el['type'] == 'way') {
        List<dynamic> nodeIds = el['nodes'];
        for (int i = 0; i < nodeIds.length - 1; i++) {
          GraphNode? n1 = graphMap[nodeIds[i]];
          GraphNode? n2 = graphMap[nodeIds[i + 1]];

          if (n1 != null && n2 != null) {
            double dist = _distanceCalc(n1.position, n2.position);
            n1.edges.add(GraphEdge(n2, dist));
            n2.edges.add(GraphEdge(n1, dist));
          }
        }
      }
    }

    List<GraphNode> nodesList = graphMap.values.toList();
    onStatusUpdate("Pruning Disconnected Pathways...");

    final routingService = RoutingService();
    List<GraphNode> phoneNodes = [];

    for (LatLng phoneLoc in blueLightPhones) {
      GraphNode nearestNode = routingService.findNearestNode(phoneLoc, nodesList);
      nearestNode.isPhone = true;
      phoneNodes.add(nearestNode);
    }

    // Flood-fill to find ONLY nodes connected to the phone network
    Set<int> reachableNodeIds = {};
    List<GraphNode> queue = List.from(phoneNodes);
    for (var p in phoneNodes) reachableNodeIds.add(p.id);

    int head = 0;
    while (head < queue.length) {
      GraphNode curr = queue[head++];
      for (GraphEdge edge in curr.edges) {
        if (!reachableNodeIds.contains(edge.target.id)) {
          reachableNodeIds.add(edge.target.id);
          queue.add(edge.target);
        }
      }
    }

    // Erase all isolated nodes so we never snap to them
    nodesList.removeWhere((node) => !reachableNodeIds.contains(node.id));
    
    // Cache the result
    _cachedGraph = nodesList;
    _cacheTimestamp = DateTime.now();

    return nodesList;
  }
  
  // Real geofencing using point-in-polygon test
  bool checkIfOnCampus(LatLng loc) {
    // Define campus boundary polygon (simplified for demo)
    final campusPolygon = [
      LatLng(minLat, minLng),
      LatLng(minLat, maxLng),
      LatLng(maxLat, maxLng),
      LatLng(maxLat, minLng),
    ];
    return _isPointInPolygon(loc, campusPolygon);
  }
  
  // Point-in-polygon ray casting algorithm
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool isInside = false;
    int i = 0;
    int j = polygon.length - 1;
    
    while (i < polygon.length) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * 
           (point.latitude - polygon[i].latitude) / 
           (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        isInside = !isInside;
      }
      j = i++;
    }
    
    return isInside;
  }
}