import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';

class QueueItem {
  final GraphNode node;
  final double distance;
  final double fScore; // For A* algorithm (g + h)
  QueueItem(this.node, this.distance, {this.fScore = 0});
}

class RoutingService {
  final Distance _distanceCalc = const Distance();
  
  // Cache for graph distances to avoid redundant computations
  Map<int, double>? _cachedDistancesFromEnd;
  GraphNode? _cachedEndNode;
  
  // Configurable detour threshold parameters
  static const double _detourBaseBuffer = 50.0; // meters
  static const double _detourPercentageMultiplier = 1.3; // 30% detour max

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
  
  // A* heuristic function (Euclidean distance)
  double _heuristic(GraphNode node, GraphNode goal) {
    return _distanceCalc(node.position, goal.position);
  }
  
  // Validate route for unrealistic jumps
  bool _isValidRoute(List<LatLng> path) {
    if (path.length < 2) return false;
    // Check for unrealistic jumps (>100m between consecutive points)
    for (int i = 0; i < path.length - 1; i++) {
      if (_distanceCalc(path[i], path[i+1]) > 100) return false;
    }
    return true;
  }
  
  // Calculate configurable detour threshold
  double _calculateDetourThreshold(double baseDistance) {
    return (baseDistance * _detourPercentageMultiplier) + _detourBaseBuffer;
  }

  // Normal Mode: Executes A* Algorithm to find the nearest phone
  List<LatLng>? calculatePathToNearestPhone(LatLng startLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    GraphNode startNode = findNearestNode(startLocation, graphNodesList);
    
    // Find nearest phone for heuristic calculation
    GraphNode? nearestPhone;
    double minPhoneDist = double.infinity;
    for (var node in graphNodesList) {
      if (node.isPhone) {
        double dist = _heuristic(startNode, node);
        if (dist < minPhoneDist) {
          minPhoneDist = dist;
          nearestPhone = node;
        }
      }
    }
    
    if (nearestPhone == null) return null;

    Map<int, double> gScores = {}; // Actual cost from start
    Map<int, GraphNode> previous = {};
    Set<int> visited = {};

    PriorityQueue<QueueItem> queue = PriorityQueue<QueueItem>(
      (a, b) => a.fScore.compareTo(b.fScore)
    );

    gScores[startNode.id] = 0;
    double hScore = _heuristic(startNode, nearestPhone);
    queue.add(QueueItem(startNode, 0, fScore: hScore));

    GraphNode? targetPhoneNode;

    while (queue.isNotEmpty) {
      GraphNode current = queue.removeFirst().node;

      if (current.isPhone) {
        targetPhoneNode = current;
        break;
      }

      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (GraphEdge edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        double newDist = gScores[current.id]! + edge.distance;

        if (newDist < (gScores[edge.target.id] ?? double.infinity)) {
          gScores[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          double hScore = _heuristic(edge.target, nearestPhone);
          queue.add(QueueItem(edge.target, newDist, fScore: newDist + hScore));
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
      List<LatLng> result = path.reversed.toList();
      return _isValidRoute(result) ? result : null;
    }
    return null;
  }

  // Helper: Standard point-to-point path calculation using A*
  List<LatLng> _calculateDijkstraPath(GraphNode startNode, GraphNode endNode) {
    if (startNode.id == endNode.id) return [startNode.position];

    Map<int, double> gScores = {};
    Map<int, GraphNode> previous = {};
    Set<int> visited = {};

    PriorityQueue<QueueItem> queue = PriorityQueue<QueueItem>(
      (a, b) => a.fScore.compareTo(b.fScore)
    );

    gScores[startNode.id] = 0;
    double hScore = _heuristic(startNode, endNode);
    queue.add(QueueItem(startNode, 0, fScore: hScore));

    while (queue.isNotEmpty) {
      GraphNode current = queue.removeFirst().node;

      if (current.id == endNode.id) break;
      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (GraphEdge edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        double newDist = gScores[current.id]! + edge.distance;

        if (newDist < (gScores[edge.target.id] ?? double.infinity)) {
          gScores[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          double hScore = _heuristic(edge.target, endNode);
          queue.add(QueueItem(edge.target, newDist, fScore: newDist + hScore));
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

  // Cached helper: Generates a map of actual WALKING distances from a starting node
  Map<int, double> _getGraphDistances(GraphNode startNode) {
    // Return cached result if available
    if (_cachedEndNode == startNode && _cachedDistancesFromEnd != null) {
      return _cachedDistancesFromEnd!;
    }
    
    Map<int, double> distances = {};
    Set<int> visited = {};

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
          queue.add(QueueItem(edge.target, newDist));
        }
      }
    }
    
    // Cache the result
    _cachedEndNode = startNode;
    _cachedDistancesFromEnd = distances;
    return distances;
  }
  
  // Clear cache when needed
  void clearCache() {
    _cachedEndNode = null;
    _cachedDistancesFromEnd = null;
  }

  // Custom Destination Mode: Hop between waypoints using true map distances
  List<LatLng>? calculatePathToDestination(LatLng startLocation, LatLng endLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    // Clear cache for fresh calculation
    clearCache();

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
        if (phoneDistToEnd < currentDistToEnd) {

          // FILTER 2: Anti-Zigzag Detour Protection with configurable threshold
          double detourDistance = phoneDistFromCurrent + phoneDistToEnd;
          double detourThreshold = _calculateDetourThreshold(currentDistToEnd);
          if (detourDistance <= detourThreshold) {

            // Find the closest valid phone
            if (phoneDistFromCurrent < minWalkingDistToPhone) {
              minWalkingDistToPhone = phoneDistFromCurrent;
              nextPhone = phone;
            }
          }
        }
      }

      // TERMINATION:
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