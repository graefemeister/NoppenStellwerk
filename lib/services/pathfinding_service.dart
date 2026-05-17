import 'dart:collection';
import '../models/track_tile.dart';

class RouteResult {
  final List<String> pathKeys;
  final Map<String, int> requiredSwitchStates;

  RouteResult(this.pathKeys, this.requiredSwitchStates);
}

class PathfindingService {
  // Sucht den kürzesten Weg vom Start zum Ziel über aneinandergrenzende Schienen
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

      for (String neighbor in _getNeighbors(currentKey, grid)) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          List<String> newPath = List.from(path)..add(neighbor);
          queue.add(newPath);
        }
      }
    }

    if (foundPath == null) return null;

    // Weg gefunden! Jetzt berechnen wir, wie die Weichen auf dem Weg stehen müssen.
    Map<String, int> requiredSwitchStates = {};
    for (int i = 0; i < foundPath.length - 1; i++) {
      String current = foundPath[i];
      String next = foundPath[i + 1];
      TrackTile tile = grid[current]!;

      if (tile.isSwitch) {
        // Ein stark vereinfachter Ansatz: Weichen schalten standardmäßig um (State 1), 
        // wenn der Weg nicht "geradeaus" weitergeht.
        // In einem voll ausgewachsenen Simulator würde man hier den Winkel zwischen current und next prüfen.
        int state = _calculateSwitchState(current, next, tile);
        requiredSwitchStates[current] = state;
      }
    }

    return RouteResult(foundPath, requiredSwitchStates);
  }

  // Sucht alle horizontalen, vertikalen und diagonalen Nachbarn, auf denen eine Schiene liegt
    static List<String> _getNeighbors(String key, Map<String, TrackTile> grid) {
    List<String> neighbors = [];
    var parts = key.split(',');
    int x = int.parse(parts[0]);
    int y = int.parse(parts[1]);

    // Wir prüfen alle Felder im Umkreis von -2 bis +2 Einheiten.
    // Dadurch findet der Algorithmus Halbschienen (Distanz 1) und ganze Schienen (Distanz 2).
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        // Das eigene Feld überspringen
        if (dx == 0 && dy == 0) continue;
        
        String nKey = "${x + dx},${y + dy}";
        if (grid.containsKey(nKey)) {
          neighbors.add(nKey);
        }
      }
    }
    return neighbors;
  }

  // Errechnet den Weichenstatus basierend auf der Abbiege-Richtung
  static int _calculateSwitchState(String currentKey, String nextKey, TrackTile tile) {
    var currParts = currentKey.split(',');
    var nextParts = nextKey.split(',');
    int dx = int.parse(nextParts[0]) - int.parse(currParts[0]);
    int dy = int.parse(nextParts[1]) - int.parse(currParts[1]);

    // Wenn sich X UND Y verändern, geht der Weg über eine Kurve / Diagonale.
    // Daher schalten wir die Weiche auf Abzweigend (State 1).
    if (dx != 0 && dy != 0) {
      return 1; 
    }
    // Geht der Weg nur horizontal oder vertikal, bleibt die Weiche auf Gerade (State 0).
    return 0;
  }
}