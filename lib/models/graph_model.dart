import 'package:latlong2/latlong.dart';

class GraphNode {
  final int id;
  final LatLng position;
  bool isPhone = false; // The magic stopping condition
  List<GraphEdge> edges = [];
  double? lightLevel; // For safety scoring
  String? zoneType; // "indoor", "outdoor", "covered"

  GraphNode(this.id, this.position);
  
  @override
  bool operator ==(Object other) => other is GraphNode && other.id == id;
  
  @override
  int get hashCode => id.hashCode;
}

class GraphEdge {
  final GraphNode target;
  final double distance; // Distance in meters

  GraphEdge(this.target, this.distance);
}