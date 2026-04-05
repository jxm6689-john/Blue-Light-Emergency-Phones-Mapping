import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';

class RoutingService {
  final Distance _distanceCalc = const Distance();

  // Snaps arbitrary coordinates to the physical graph
  GraphNode findNearestNode(LatLng target, List<GraphNode> nodes) {
    GraphNode nearest = nodes.first;
    double minDist = double.infinity;

    for (var node in nodes) {
      double dist = _distanceCalc(target, node.position);
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }
    return nearest;
  }

  // Executes Dijkstra's Algorithm
  List<LatLng>? calculatePathToNearestPhone(LatLng startLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    GraphNode startNode = findNearestNode(startLocation, graphNodesList);
    Map<int, double> distances = {};
    Map<int, GraphNode> previous = {};
    Set<int> visited = {};

    PriorityQueue<GraphNode> queue = PriorityQueue((a, b) =>
        (distances[a.id] ?? double.infinity).compareTo(distances[b.id] ?? double.infinity)
    );

    distances[startNode.id] = 0;
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

        double newDist = distances[current.id]! + edge.distance;

        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          queue.add(edge.target);
        }
      }
    }

    // Trace the path backwards
    if (targetPhoneNode != null) {
      List<LatLng> path = [];
      GraphNode? curr = targetPhoneNode;
      while (curr != null) {
        path.add(curr.position);
        curr = previous[curr.id];
      }
      return path.reversed.toList();
    }
    return null;
  }
}