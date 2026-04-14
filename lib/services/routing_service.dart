import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';

class QueueItem {
  final GraphNode node;
  final double distance;
  QueueItem(this.node, this.distance);
}

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

  // Normal Mode: Executes Dijkstra's Algorithm to find the nearest phone
// Normal Mode: Executes Dijkstra's Algorithm to find the nearest phone
  List<LatLng>? calculatePathToNearestPhone(LatLng startLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    GraphNode startNode = findNearestNode(startLocation, graphNodesList);
    Map<int, double> distances = {};
    Map<int, GraphNode> previous = {};
    Set<int> visited = {};

    // CORRECTED: PriorityQueue now compares the frozen distance in QueueItem
    PriorityQueue<QueueItem> queue = PriorityQueue<QueueItem>(
            (a, b) => a.distance.compareTo(b.distance)
    );

    distances[startNode.id] = 0;
    queue.add(QueueItem(startNode, 0));

    GraphNode? targetPhoneNode;

    while (queue.isNotEmpty) {
      // Extract the node from the wrapper
      GraphNode current = queue.removeFirst().node;

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
          // CORRECTED: Wrap the target and its new distance in a QueueItem
          queue.add(QueueItem(edge.target, newDist));
        }
      }
    }

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

  // Helper: Standard point-to-point path calculation
// Helper: Standard point-to-point path calculation
  List<LatLng> _calculateDijkstraPath(GraphNode startNode, GraphNode endNode) {
    if (startNode.id == endNode.id) return [startNode.position];

    Map<int, double> distances = {};
    Map<int, GraphNode> previous = {};
    Set<int> visited = {};

    // CORRECTED: PriorityQueue using QueueItem
    PriorityQueue<QueueItem> queue = PriorityQueue<QueueItem>(
            (a, b) => a.distance.compareTo(b.distance)
    );

    distances[startNode.id] = 0;
    queue.add(QueueItem(startNode, 0));

    while (queue.isNotEmpty) {
      GraphNode current = queue.removeFirst().node;

      if (current.id == endNode.id) break;
      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (GraphEdge edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        double newDist = distances[current.id]! + edge.distance;

        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          // CORRECTED: Add to queue via QueueItem
          queue.add(QueueItem(edge.target, newDist));
        }
      }
    }

    if (previous.containsKey(endNode.id)) {
      List<LatLng> path = [];
      GraphNode? curr = endNode;
      while (curr != null) {
        path.add(curr.position);
        curr = previous[curr.id];
      }
      return path.reversed.toList();
    }
    return [];
  }

  // NEW HELPER: Generates a map of actual WALKING distances from a starting node to all other nodes.
// NEW HELPER: Generates a map of actual WALKING distances from a starting node to all other nodes.
  Map<int, double> _getGraphDistances(GraphNode startNode) {
    Map<int, double> distances = {};
    Set<int> visited = {};

    // CORRECTED: PriorityQueue using QueueItem
    PriorityQueue<QueueItem> queue = PriorityQueue<QueueItem>(
            (a, b) => a.distance.compareTo(b.distance)
    );

    distances[startNode.id] = 0;
    queue.add(QueueItem(startNode, 0));

    while (queue.isNotEmpty) {
      GraphNode current = queue.removeFirst().node;

      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (GraphEdge edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        double newDist = distances[current.id]! + edge.distance;

        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          // CORRECTED: Add to queue via QueueItem
          queue.add(QueueItem(edge.target, newDist));
        }
      }
    }
    return distances;
  }

  // Custom Destination Mode: Hop between waypoints using true map distances
  List<LatLng>? calculatePathToDestination(LatLng startLocation, LatLng endLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    GraphNode currentNode = findNearestNode(startLocation, graphNodesList);
    GraphNode endNode = findNearestNode(endLocation, graphNodesList);

    // Pre-calculate the WALKING distance from the destination backward to every other point.
    Map<int, double> distFromEnd = _getGraphDistances(endNode);

    List<GraphNode> unvisitedPhones = graphNodesList.where((n) => n.isPhone).toList();
    unvisitedPhones.removeWhere((p) => p.id == currentNode.id);

    List<LatLng> completePath = [];

    while (true) {
      // Calculate WALKING distances from our current location to all other points
      Map<int, double> distFromCurrent = _getGraphDistances(currentNode);
      double currentDistToEnd = distFromEnd[currentNode.id] ?? double.infinity;

      GraphNode? nextPhone;
      double minWalkingDistToPhone = double.infinity;

      for (var phone in unvisitedPhones) {
        double phoneDistFromCurrent = distFromCurrent[phone.id] ?? double.infinity;
        double phoneDistToEnd = distFromEnd[phone.id] ?? double.infinity;

        // FILTER 1: Strict Forward Progress
        // Walking from this phone to the end MUST be shorter than walking from our current spot to the end.
        if (phoneDistToEnd < currentDistToEnd) {

          // FILTER 2: Anti-Zigzag Detour Protection
          // Prevent the algorithm from picking a phone that requires a massive detour to reach.
          // We allow the path to be extended by 50% (multiplier 1.5) to hit a phone, but no more.
          double detourDistance = phoneDistFromCurrent + phoneDistToEnd;
          if (detourDistance <= (currentDistToEnd * 1.5) + 25.0) {

            // Find the closest valid phone
            if (phoneDistFromCurrent < minWalkingDistToPhone) {
              minWalkingDistToPhone = phoneDistFromCurrent;
              nextPhone = phone;
            }
          }
        }
      }

      // TERMINATION:
      // If we run out of valid phones, OR the destination is a shorter walk than the closest valid phone.
      if (nextPhone == null || currentDistToEnd <= minWalkingDistToPhone) {
        List<LatLng> segment = _calculateDijkstraPath(currentNode, endNode);
        _appendSegment(completePath, segment);
        break;
      } else {
        // Build path to the selected phone
        List<LatLng> segment = _calculateDijkstraPath(currentNode, nextPhone);
        _appendSegment(completePath, segment);

        // Move the "Current Node" to the phone we just reached
        currentNode = nextPhone;
        unvisitedPhones.removeWhere((p) => p.id == currentNode.id);
      }
    }

    return completePath.isNotEmpty ? completePath : null;
  }

  // Smoothly stitch the path segments together
  void _appendSegment(List<LatLng> fullPath, List<LatLng> segment) {
    if (segment.isEmpty) return;
    if (fullPath.isNotEmpty && fullPath.last == segment.first) {
      fullPath.addAll(segment.skip(1));
    } else {
      fullPath.addAll(segment);
    }
  }
}