import 'package:latlong2/latlong.dart';

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