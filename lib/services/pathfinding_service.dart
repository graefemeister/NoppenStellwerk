import 'dart:collection';
import 'dart:math' as math;
import '../models/track_tile.dart';

class RouteResult {
  final List<String> pathKeys;
  final Map<String, int> requiredSwitchStates;

  RouteResult(this.pathKeys, this.requiredSwitchStates);
}

class PathfindingService {
  static RouteResult? findRoute(Map<String, TrackTile> grid, String startKey, String targetKey) {
    if (!grid.containsKey(startKey) || !grid.containsKey(targetKey)) return null;

    Queue<List<String>> queue = Queue();
    Set<String> visited = {startKey};

    queue.add([startKey]);
    List<String>? foundPath;

    while (queue.isNotEmpty) {
      List<String> path = queue.removeFirst();
      String currentKey = path.last;

      if (currentKey == targetKey) {
        foundPath = path;
        break;
      }

      for (String neighbor in _getValidNeighbors(currentKey, grid)) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          List<String> newPath = List.from(path)..add(neighbor);
          queue.add(newPath);
        }
      }
    }

    if (foundPath == null) return null;

    Map<String, int> requiredSwitchStates = {};
    for (int i = 0; i < foundPath.length - 1; i++) {
      String current = foundPath[i];
      TrackTile tile = grid[current]!;

      if (tile.isSwitch) {
        String prev = i > 0 ? foundPath[i - 1] : "";
        String next = foundPath[i + 1];
        requiredSwitchStates[current] = _calculateSwitchState(prev, current, next, tile);
      }
    }

    return RouteResult(foundPath, requiredSwitchStates);
  }

  static Map<String, int> recalculateSwitchStates(List<String> combinedPath, Map<String, TrackTile> grid) {
    Map<String, int> requiredStates = {};
    for (int i = 0; i < combinedPath.length - 1; i++) {
      String current = combinedPath[i];
      TrackTile tile = grid[current]!;

      if (tile.isSwitch) {
        String prev = i > 0 ? combinedPath[i - 1] : "";
        String next = combinedPath[i + 1];
        requiredStates[current] = _calculateSwitchState(prev, current, next, tile);
      }
    }
    return requiredStates;
  }

  // Physikalische Ausgänge (0=Ost, 2=Süd, 4=West, 6=Nord, ungerade=Diagonal)
  static List<int> _getExits(TrackTile tile) {
    int r = tile.rotation;
    switch (tile.type) {
      case TileType.straight:
      case TileType.halfStraight: 
        return [r % 8, (r + 4) % 8];
      case TileType.crossing: 
        return [r % 8, (r + 2) % 8, (r + 4) % 8, (r + 6) % 8];
      case TileType.switchLeft: 
        return [(r + 4) % 8, r % 8, (r + 7) % 8]; // Wurzel, Gerade, Links
      case TileType.switchRight: 
        return [(r + 4) % 8, r % 8, (r + 1) % 8]; // Wurzel, Gerade, Rechts
      case TileType.threeWay: 
        return [(r + 4) % 8, r % 8, (r + 7) % 8, (r + 1) % 8];
      case TileType.doubleSlip: 
        return [0, 1, 2, 3, 4, 5, 6, 7]; 
      case TileType.buffer: 
        return [(r + 4) % 8];
    }
  }

  // HILFSFUNKTION: Das Herzstück der "Verzeihenden Topologie"
  // Gibt Gleisen eine Fang-Toleranz von +/- 45 Grad, um das harte Raster zu umgehen!
  static bool _hasFuzzyExit(List<int> exits, int targetDir) {
    for (int e in exits) {
      if (e == targetDir || e == (targetDir + 1) % 8 || e == (targetDir + 7) % 8) {
        return true;
      }
    }
    return false;
  }

  static List<String> _getValidNeighbors(String key, Map<String, TrackTile> grid) {
    List<String> neighbors = [];
    TrackTile tileA = grid[key]!;
    var pA = key.split(',');
    int ax = int.parse(pA[0]); 
    int ay = int.parse(pA[1]);

    List<int> exitsA = _getExits(tileA);

    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        
        String nKey = "${ax + dx},${ay + dy}";
        if (grid.containsKey(nKey)) {
          TrackTile tileB = grid[nKey]!;
          List<int> exitsB = _getExits(tileB);
          
          int dirAB = _getClosestDirection(dx, dy);
          int dirBA = (dirAB + 4) % 8; 

          // DER MAGISCHE FIX:
          // 1. Das && (UND) stoppt das Schummeln an den Weichen-Außenseiten.
          // 2. Das _hasFuzzyExit erlaubt deinen Diagonalen aber das Einrasten.
          if (_hasFuzzyExit(exitsA, dirAB) && _hasFuzzyExit(exitsB, dirBA)) {
            neighbors.add(nKey);
          }
        }
      }
    }
    return neighbors;
  }

  static int _calculateSwitchState(String prevKey, String currentKey, String nextKey, TrackTile tile) {
    var currParts = currentKey.split(',');
    int cx = int.parse(currParts[0]);
    int cy = int.parse(currParts[1]);

    var nextParts = nextKey.split(',');
    int nx = int.parse(nextParts[0]);
    int ny = int.parse(nextParts[1]);

    int outDir = _getClosestDirection(nx - cx, ny - cy);
    int relOut = (outDir - tile.rotation + 8) % 8;
    
    int relIn = -1;
    if (prevKey.isNotEmpty) {
      var prevParts = prevKey.split(',');
      int px = int.parse(prevParts[0]);
      int py = int.parse(prevParts[1]);
      int inDir = _getClosestDirection(px - cx, py - cy); 
      relIn = (inDir - tile.rotation + 8) % 8;
    }

    bool uses(int dir) => relOut == dir || relIn == dir;

    switch (tile.type) {
      case TileType.switchLeft:
        if (uses(5) || uses(6) || uses(7)) return 1; // Abzweig Links
        return 0; 
      case TileType.switchRight:
        if (uses(1) || uses(2) || uses(3)) return 1; // Abzweig Rechts
        return 0; 
      case TileType.threeWay:
        if (uses(5) || uses(6) || uses(7)) return 1; // Links
        if (uses(1) || uses(2) || uses(3)) return 2; // Rechts
        return 0;
      case TileType.doubleSlip:
        bool w = uses(3) || uses(4) || uses(5);
        bool e = uses(7) || uses(0) || uses(1);
        bool n = uses(5) || uses(6) || uses(7);
        bool s = uses(1) || uses(2) || uses(3);
        
        if (w && s) return 2;
        if (e && n) return 3;
        if (n && s) return 1;
        return 0;
      default:
        return 0;
    }
  }

  static int _getClosestDirection(int dx, int dy) {
    double angle = math.atan2(dy, dx);
    return ((angle / (math.pi / 4)).round() + 8) % 8;
  }
}