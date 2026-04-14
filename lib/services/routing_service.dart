import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:collection/collection.dart';
import 'package:blue_light_emergency_phones_mapping/models/graph_model.dart';

class QueueItem {
  final GraphNode node;
  final double distance;
  final double totalCost; // distance + heuristic for A*
  QueueItem(this.node, this.distance, this.totalCost);
}

class AStarNode {
  final GraphNode node;
  final double gScore; // Cost from start
  final double fScore; // gScore + heuristic
  final int? previousId;
  
  AStarNode({
    required this.node,
    required this.gScore,
    required this.fScore,
    this.previousId,
  });
}

class RoutingService {
  final Distance _distanceCalc = const Distance();
  static const double _earthRadius = 6371000; // meters
  
  /// Snaps arbitrary coordinates to the physical graph with improved logic
  /// Considers walkable distance and optionally user heading for better UX
  GraphNode findNearestNode(
    LatLng target, 
    List<GraphNode> nodes, {
    LatLng? previousLocation,
    double headingWeight = 0.3,
  }) {
    if (nodes.isEmpty) throw StateError('Node list cannot be empty');
    
    GraphNode nearest = nodes.first;
    double minScore = double.infinity;
    
    // Calculate heading vector if previous location is provided
    math.Point<double>? headingVector;
    if (previousLocation != null) {
      final dLat = target.latitude - previousLocation.latitude;
      final dLon = target.longitude - previousLocation.longitude;
      headingVector = math.Point(dLat, dLon);
      final magnitude = headingVector.distance;
      if (magnitude > 0) {
        headingVector = math.Point(
          headingVector.x / magnitude,
          headingVector.y / magnitude,
        );
      }
    }
    
    for (var node in nodes) {
      final euclideanDist = _distanceCalc(target, node.position);
      
      // Base score is the Euclidean distance
      double score = euclideanDist;
      
      // Apply heading bonus if we have direction information
      if (headingVector != null) {
        final nodeDx = node.position.latitude - target.latitude;
        final nodeDy = node.position.longitude - target.longitude;
        final nodeMagnitude = math.sqrt(nodeDx * nodeDx + nodeDy * nodeDy);
        
        if (nodeMagnitude > 0) {
          final nodeDirection = math.Point(
            nodeDx / nodeMagnitude,
            nodeDy / nodeMagnitude,
          );
          
          // Dot product gives us alignment (-1 to 1)
          final alignment = headingVector!.x * nodeDirection.x + 
                           headingVector!.y * nodeDirection.y;
          
          // Reduce score for nodes in the direction of travel
          // alignment=1 (same direction) -> multiplier=0.7
          // alignment=-1 (opposite) -> multiplier=1.3
          final headingMultiplier = 1.0 - (headingWeight * alignment);
          score *= headingMultiplier;
        }
      }
      
      if (score < minScore) {
        minScore = score;
        nearest = node;
      }
    }
    return nearest;
  }

  /// Haversine distance heuristic for A* (in meters)
  double _haversineHeuristic(LatLng from, LatLng to) {
    return _distanceCalc(from, to);
  }

  /// A* pathfinding algorithm with haversine heuristic
  /// More efficient than Dijkstra for point-to-point routing
  List<LatLng>? _astarPath(GraphNode startNode, GraphNode endNode) {
    if (startNode.id == endNode.id) return [startNode.position];

    final openSet = PriorityQueue<AStarNode>(
      (a, b) => a.fScore.compareTo(b.fScore),
    );
    
    final Map<int, double> gScores = {startNode.id: 0};
    final Map<int, int> cameFrom = {};
    
    final double heuristic = _haversineHeuristic(startNode.position, endNode.position);
    openSet.add(AStarNode(
      node: startNode,
      gScore: 0,
      fScore: heuristic,
    ));

    while (openSet.isNotEmpty) {
      final current = openSet.removeFirst();
      
      if (current.node.id == endNode.id) {
        // Reconstruct path
        final List<LatLng> path = [endNode.position];
        int? currentId = endNode.id;
        while (cameFrom.containsKey(currentId)) {
          currentId = cameFrom[currentId];
          final node = _getNodeById(currentId!, [startNode, endNode]);
          if (node != null) path.add(node.position);
        }
        return path.reversed.toList();
      }

      for (final edge in current.node.edges) {
        final tentativeG = current.gScore + edge.distance;
        
        if (tentativeG < (gScores[edge.target.id] ?? double.infinity)) {
          cameFrom[edge.target.id] = current.node.id;
          gScores[edge.target.id] = tentativeG;
          
          final h = _haversineHeuristic(edge.target.position, endNode.position);
          openSet.add(AStarNode(
            node: edge.target,
            gScore: tentativeG,
            fScore: tentativeG + h,
          ));
        }
      }
    }

    return null; // No path found
  }

  /// Helper to find a node by ID from a list
  GraphNode? _getNodeById(int id, List<GraphNode> nodes) {
    for (final node in nodes) {
      if (node.id == id) return node;
      for (final edge in node.edges) {
        if (edge.target.id == id) return edge.target;
      }
    }
    return null;
  }

  /// Optimized Dijkstra from destination - runs once and gives distances to all nodes
  Map<int, double> _dijkstraFromDestination(GraphNode destinationNode) {
    final Map<int, double> distances = {destinationNode.id: 0};
    final Map<int, GraphNode> previous = {};
    final visited = <int>{};
    
    final queue = PriorityQueue<QueueItem>(
      (a, b) => a.totalCost.compareTo(b.totalCost),
    );
    queue.add(QueueItem(destinationNode, 0, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      
      if (visited.contains(current.node.id)) continue;
      visited.add(current.node.id);

      for (final edge in current.node.edges) {
        if (visited.contains(edge.target.id)) continue;

        final newDist = current.distance + edge.distance;
        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          previous[edge.target.id] = current.node;
          queue.add(QueueItem(edge.target, newDist, newDist));
        }
      }
    }

    return distances;
  }

  /// Normal Mode: Executes optimized Dijkstra to find the nearest phone
  List<LatLng>? calculatePathToNearestPhone(LatLng startLocation, List<GraphNode> graphNodesList) {
    if (graphNodesList.isEmpty) return null;

    final GraphNode startNode = findNearestNode(startLocation, graphNodesList);
    final Map<int, double> distances = {};
    final Map<int, GraphNode> previous = {};
    final Set<int> visited = {};

    final queue = PriorityQueue<QueueItem>(
      (a, b) => a.totalCost.compareTo(b.totalCost),
    );

    distances[startNode.id] = 0;
    queue.add(QueueItem(startNode, 0, 0));

    GraphNode? targetPhoneNode;

    while (queue.isNotEmpty) {
      final current = queue.removeFirst().node;

      if (current.isPhone) {
        targetPhoneNode = current;
        break;
      }

      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (final edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        final newDist = distances[current.id]! + edge.distance;

        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          queue.add(QueueItem(edge.target, newDist, newDist));
        }
      }
    }

    if (targetPhoneNode != null) {
      final List<LatLng> path = [];
      GraphNode? curr = targetPhoneNode;
      while (curr != null) {
        path.add(curr.position);
        curr = previous[curr.id];
      }
      return simplifyPath(path.reversed.toList());
    }
    return null;
  }

  /// Optimized point-to-point path using A* algorithm
  List<LatLng> _calculateDijkstraPath(GraphNode startNode, GraphNode endNode) {
    if (startNode.id == endNode.id) return [startNode.position];

    // Use A* for better performance on point-to-point routing
    final result = _astarPath(startNode, endNode);
    if (result != null) {
      return simplifyPath(result);
    }
    
    // Fallback to Dijkstra if A* fails
    final Map<int, double> distances = {startNode.id: 0};
    final Map<int, GraphNode> previous = {};
    final Set<int> visited = {};

    final queue = PriorityQueue<QueueItem>(
      (a, b) => a.totalCost.compareTo(b.totalCost),
    );
    queue.add(QueueItem(startNode, 0, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst().node;

      if (current.id == endNode.id) break;
      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      for (final edge in current.edges) {
        if (visited.contains(edge.target.id)) continue;

        final newDist = distances[current.id]! + edge.distance;

        if (newDist < (distances[edge.target.id] ?? double.infinity)) {
          distances[edge.target.id] = newDist;
          previous[edge.target.id] = current;
          queue.add(QueueItem(edge.target, newDist, newDist));
        }
      }
    }

    if (previous.containsKey(endNode.id)) {
      final List<LatLng> path = [];
      GraphNode? curr = endNode;
      while (curr != null) {
        path.add(curr.position);
        curr = previous[curr.id];
      }
      return simplifyPath(path.reversed.toList());
    }
    return [];
  }

  /// Douglas-Peucker algorithm for path simplification
  /// Reduces number of points while preserving path shape
  List<LatLng> simplifyPath(List<LatLng> path, {double tolerance = 3.0}) {
    if (path.length <= 2) return path;

    final simplified = _douglasPeucker(path, tolerance);
    return simplified;
  }

  List<LatLng> _douglasPeucker(List<LatLng> points, double epsilon) {
    if (points.length <= 2) return points;

    // Find the point with the maximum distance from the line segment
    double dmax = 0;
    int index = 0;
    final end = points.length - 1;

    for (int i = 1; i < end; i++) {
      final d = _perpendicularDistance(points[i], points[0], points[end]);
      if (d > dmax) {
        index = i;
        dmax = d;
      }
    }

    // If max distance is greater than epsilon, recursively simplify
    if (dmax > epsilon) {
      final recResults1 = _douglasPeucker(
        points.sublist(0, index + 1),
        epsilon,
      );
      final recResults2 = _douglasPeucker(
        points.sublist(index),
        epsilon,
      );

      return [
        ...recResults1.take(recResults1.length - 1),
        ...recResults2,
      ];
    } else {
      return [points[0], points[end]];
    }
  }

  /// Calculate perpendicular distance from point to line segment
  double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;

    if (dx == 0 && dy == 0) {
      return _distanceCalc(point, lineStart);
    }

    final t = ((point.longitude - lineStart.longitude) * dx +
               (point.latitude - lineStart.latitude) * dy) /
              (dx * dx + dy * dy);

    final closestX = lineStart.longitude + t * dx;
    final closestY = lineStart.latitude + t * dy;
    final closest = LatLng(closestY, closestX);

    return _distanceCalc(point, closest);
  }

  /// Custom Destination Mode: Optimized with single Dijkstra run from destination
  List<LatLng>? calculatePathToDestination(
    LatLng startLocation, 
    LatLng endLocation, 
    List<GraphNode> graphNodesList,
  ) {
    if (graphNodesList.isEmpty) return null;

    final currentNode = findNearestNode(startLocation, graphNodesList);
    final endNode = findNearestNode(endLocation, graphNodesList);

    // OPTIMIZATION: Run Dijkstra ONCE from destination to get all distances
    // This eliminates the O(n²) complexity of calling _getGraphDistances in a loop
    final distFromEnd = _dijkstraFromDestination(endNode);

    var unvisitedPhones = graphNodesList.where((n) => n.isPhone).toSet();
    unvisitedPhones.removeWhere((p) => p.id == currentNode.id);

    final List<LatLng> completePath = [];
    var current = currentNode;

    while (true) {
      // Get distance from current node to end (already computed)
      final currentDistToEnd = distFromEnd[current.id] ?? double.infinity;

      GraphNode? nextPhone;
      double minWalkingDistToPhone = double.infinity;

      for (final phone in unvisitedPhones) {
        final phoneDistFromCurrent = _getSingleSourceDistance(current, phone);
        final phoneDistToEnd = distFromEnd[phone.id] ?? double.infinity;

        // FILTER 1: Strict Forward Progress
        if (phoneDistToEnd < currentDistToEnd) {
          // FILTER 2: Anti-Zigzag Detour Protection
          final detourDistance = phoneDistFromCurrent + phoneDistToEnd;
          if (detourDistance <= (currentDistToEnd * 1.5) + 25.0) {
            if (phoneDistFromCurrent < minWalkingDistToPhone) {
              minWalkingDistToPhone = phoneDistFromCurrent;
              nextPhone = phone;
            }
          }
        }
      }

      // TERMINATION: No valid phones or destination is closer
      if (nextPhone == null || currentDistToEnd <= minWalkingDistToPhone) {
        final segment = _calculateDijkstraPath(current, endNode);
        _appendSegment(completePath, segment);
        break;
      } else {
        final segment = _calculateDijkstraPath(current, nextPhone);
        _appendSegment(completePath, segment);
        current = nextPhone;
        unvisitedPhones.removeWhere((p) => p.id == current.id);
      }
    }

    return completePath.isNotEmpty ? simplifyPath(completePath) : null;
  }

  /// Helper to get distance between two nodes using cached graph traversal
  double _getSingleSourceDistance(GraphNode from, GraphNode to) {
    // Quick BFS/Dijkstra to find single distance
    final visited = <int>{};
    final queue = PriorityQueue<_DistanceNode>(
      (a, b) => a.distance.compareTo(b.distance),
    );
    queue.add(_DistanceNode(from.id, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.nodeId == to.id) return current.distance;
      if (visited.contains(current.nodeId)) continue;
      visited.add(current.nodeId);

      // Find the actual node to get its edges
      final node = _findNodeById(current.nodeId, from, to);
      if (node == null) continue;

      for (final edge in node.edges) {
        if (!visited.contains(edge.target.id)) {
          queue.add(_DistanceNode(
            edge.target.id,
            current.distance + edge.distance,
          ));
        }
      }
    }
    return double.infinity;
  }

  GraphNode? _findNodeById(int id, GraphNode start, GraphNode end) {
    if (start.id == id) return start;
    if (end.id == id) return end;
    // Search through edges
    for (final edge in start.edges) {
      if (edge.target.id == id) return edge.target;
    }
    for (final edge in end.edges) {
      if (edge.target.id == id) return edge.target;
    }
    return null;
  }

  /// Smoothly stitch the path segments together
  void _appendSegment(List<LatLng> fullPath, List<LatLng> segment) {
    if (segment.isEmpty) return;
    if (fullPath.isNotEmpty && fullPath.last == segment.first) {
      fullPath.addAll(segment.skip(1));
    } else {
      fullPath.addAll(segment);
    }
  }
}

class _DistanceNode {
  final int nodeId;
  final double distance;
  _DistanceNode(this.nodeId, this.distance);
}