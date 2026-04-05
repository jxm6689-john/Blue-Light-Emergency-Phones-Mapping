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

  Future<List<GraphNode>> fetchAndBuildGraph(Function(String) onStatusUpdate) async {
    onStatusUpdate("Downloading Campus Pathways...");

    final String query = '''
      [out:json];
      (
        way["highway"~"footway|path|pedestrian"]($minLat,$minLng,$maxLat,$maxLng);
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

    // Extract raw nodes
    for (var el in elements) {
      if (el['type'] == 'node') {
        int id = el['id'];
        graphMap[id] = GraphNode(id, LatLng(el['lat'], el['lon']));
      }
    }

    // Connect the edges
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
    onStatusUpdate("Mapping Emergency Phones...");

    final routingService = RoutingService();
    // Snap the phones to the graph
    for (LatLng phoneLoc in blueLightPhones) {
      GraphNode nearestNode = routingService.findNearestNode(phoneLoc, nodesList);
      nearestNode.isPhone = true;
    }

    return nodesList;
  }

  bool checkIfOnCampus(LatLng loc) {
    return true; // Re-enable geofence math here if desired
  }
}