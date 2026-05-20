import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:convert';                  
import '../models/track_tile.dart';
import '../widgets/track_painter.dart';
import '../localization.dart';           
import 'settings_screen.dart';  
import '../services/pathfinding_service.dart';       

class StellwerkScreen extends StatefulWidget {
  final Map<String, TrackTile> grid;
  final Function(Map<String, TrackTile>) onGridChanged;
  final VoidCallback onOpenEditor; 
  final VoidCallback onSettingsRefresh; 

  const StellwerkScreen({
    super.key, 
    required this.grid, 
    required this.onGridChanged, 
    required this.onOpenEditor,
    required this.onSettingsRefresh,
  });

  @override
  State<StellwerkScreen> createState() => _StellwerkScreenState();
}

class _StellwerkScreenState extends State<StellwerkScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  final double _snapSize = 30.0; 
  final double _tileSize = 60.0;
  
  bool _configMode = false; 

  // --- FAHRSTRASSEN STATE ---
  bool _isRoutingMode = false; // Ist der "Stellen"-Modus aktiv?
  String? _routeStart;         // Gemerkter Startpunkt
  String? _routeVia;          // Speichert das Zwischenziel
  bool _expectingVia = false; // Steuert, ob der nächste Tap ein Zwischenziel ist
  Set<String> _activeRoute = {}; // Die aktuell leuchtende Fahrstraße
  Map<String, int> _activeSwitchStates = {}; // Merkt sich die Zustände für den Painter

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.translationValues(-1000, -1000, 0);
  }

  void _handleTap(TapUpDetails details) {
    final RenderBox renderBox = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final Offset localPos = renderBox.globalToLocal(details.globalPosition);
    final int gridX = (localPos.dx / _snapSize).round();
    final int gridY = (localPos.dy / _snapSize).round();
    final String clickedKey = "$gridX,$gridY";

    if (!widget.grid.containsKey(clickedKey)) return;

    if (_isRoutingMode) {
      if (_routeStart == null) {
        // Start wählen
        setState(() => _routeStart = clickedKey);
      } 
      else if (_expectingVia && _routeVia == null) {
        // Zwischenziel wählen (verhindert, dass Start nochmal angetippt wird)
        if (clickedKey == _routeStart) return; 
        setState(() {
          _routeVia = clickedKey;
          _expectingVia = false; // Modus beenden, nächster Klick ist das Ziel
        });
      } 
      else {
        // Ziel wählen
        if (clickedKey == _routeStart || clickedKey == _routeVia) {
          // Klickt man aus Versehen nochmal auf Start/Via, brechen wir nicht ab, 
          // sondern warten einfach weiter auf das echte Ziel.
          return; 
        }
        _calculateAndSetRoute(clickedKey);
      }
    } else {
      // Manueller Modus (Weichen stellen)
      final tile = widget.grid[clickedKey]!;
      if (tile.isSwitch) {
        final newGrid = Map<String, TrackTile>.from(widget.grid);
        int maxStates = tile.type == TileType.threeWay ? 3 : (tile.type == TileType.doubleSlip ? 4 : 2);
        newGrid[clickedKey] = tile.copyWith(switchState: (tile.switchState + 1) % maxStates);
        widget.onGridChanged(newGrid);
      }
    }
  }

  void _calculateAndSetRoute(String targetKey) {
    RouteResult? finalResult;

    if (_routeVia != null) {
      // ROUTE MIT ZWISCHENZIEL: Zwei Teilstrecken berechnen
      final segment1 = PathfindingService.findRoute(widget.grid, _routeStart!, _routeVia!);
      final segment2 = PathfindingService.findRoute(widget.grid, _routeVia!, targetKey);

      if (segment1 != null && segment2 != null) {
        // 1. Pfade verknüpfen (Doppelung des Via-Keys entfernen)
        List<String> combinedPath = List.from(segment1.pathKeys);
        if (segment2.pathKeys.isNotEmpty) {
          combinedPath.addAll(segment2.pathKeys.sublist(1));
        }

        // 2. NEU: Die Weichen für die GESAMTE verbundene Strecke in einem Rutsch berechnen!
        Map<String, int> combinedSwitches = PathfindingService.recalculateSwitchStates(combinedPath, widget.grid);

        finalResult = RouteResult(combinedPath, combinedSwitches);
      }
    } else {
      // NORMALE ROUTE: Direkt von Start nach Ziel
      finalResult = PathfindingService.findRoute(widget.grid, _routeStart!, targetKey);
    }

    if (finalResult != null) {
      // Weichen im echten Grid umstellen
      final newGrid = Map<String, TrackTile>.from(widget.grid);
      finalResult.requiredSwitchStates.forEach((key, state) {
        newGrid[key] = newGrid[key]!.copyWith(switchState: state);
      });
      widget.onGridChanged(newGrid);

      setState(() {
        _activeRoute = finalResult!.pathKeys.toSet();
        _activeSwitchStates = finalResult.requiredSwitchStates;
        _isRoutingMode = false;
        _routeStart = null;
        _routeVia = null;
        _expectingVia = false;
      });
    } else {
      // Fehler: Keine physikalische Verbindung möglich
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kein physikalischer Weg gefunden!"), backgroundColor: Colors.red),
      );
    }
  }

  // Baut den dynamischen Bedien-Button unten im Bildschirm um
  Widget _buildRouteFab() {
    if (!_isRoutingMode && _activeRoute.isEmpty) {
      return FloatingActionButton.extended(
        onPressed: () => setState(() => _isRoutingMode = true),
        label: const Text("Fahrstraße stellen"),
        icon: const Icon(Icons.gesture),
      );
    }

    if (_isRoutingMode) {
      if (_routeStart == null) {
        return FloatingActionButton.extended(
          onPressed: () => setState(() { _isRoutingMode = false; }),
          label: const Text("Abbrechen (Startgleis wählen...)"),
          icon: const Icon(Icons.close),
          backgroundColor: Colors.orange,
        );
      }

      // Start ist gewählt. Jetzt bieten wir die "Via"-Option an!
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_routeVia == null) ...[
            FloatingActionButton.extended(
              onPressed: () => setState(() => _expectingVia = !_expectingVia),
              label: Text(_expectingVia ? "-> Tippe Zwischenziel..." : "+ Zwischenziel"),
              icon: Icon(_expectingVia ? Icons.touch_app : Icons.add_location),
              backgroundColor: _expectingVia ? Colors.lightBlue : Colors.blueGrey,
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton.extended(
            onPressed: () => setState(() {
              _isRoutingMode = false;
              _routeStart = null;
              _routeVia = null;
              _expectingVia = false;
            }),
            label: Text(_routeVia != null 
                ? "Ziel wählen... (Via aktiv)" 
                : "Ziel wählen..."),
            icon: const Icon(Icons.flag),
            backgroundColor: Colors.green,
          ),
        ],
      );
    }

    // Fahrstraße aktiv -> Auflösen-Button
    return FloatingActionButton.extended(
      onPressed: () {
        setState(() {
          _activeRoute.clear();
          _activeSwitchStates.clear();
        });
      },
      label: const Text("Fahrstraße auflösen"),
      icon: const Icon(Icons.delete_forever),
      backgroundColor: Colors.redAccent,
    );
  }

  void _cycleSwitchState(String key, TrackTile tile) {
    Map<String, TrackTile> newGrid = Map.from(widget.grid);
    TrackTile updatedTile = tile.copy();

    int maxStates = 1;
    if (tile.type == TileType.switchLeft || tile.type == TileType.switchRight) maxStates = 2;
    if (tile.type == TileType.threeWay) maxStates = 3;
    if (tile.type == TileType.doubleSlip) maxStates = 4;

    updatedTile.switchState = (updatedTile.switchState + 1) % maxStates;
    newGrid[key] = updatedTile;
    widget.onGridChanged(newGrid);
  }

 
  // ... [Export, Import und ConfigDialog Methoden bleiben exakt gleich] ...
  void _exportGrid() {
    final Map<String, dynamic> exportData = widget.grid.map((k, v) => MapEntry(k, v.toJson()));
    Clipboard.setData(ClipboardData(text: jsonEncode(exportData)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('plan_copied'.tr), backgroundColor: Colors.green));
  }

  void _importGrid() {
    final TextEditingController importController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('import_trackplan_title'.tr),
        content: TextField(controller: importController, maxLines: 5, decoration: InputDecoration(hintText: 'paste_json_hint'.tr, border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () {
              try {
                final Map<String, dynamic> decoded = jsonDecode(importController.text);
                widget.onGridChanged(decoded.map((k, v) => MapEntry(k, TrackTile.fromJson(v))));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('plan_loaded_success'.tr), backgroundColor: Colors.green));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('plan_load_error'.tr), backgroundColor: Colors.redAccent));
              }
            },
            child: Text('load'.tr),
          )
        ],
      ),
    );
  }

  void _showConfigDialog(String key, TrackTile tile) {
    List<TextEditingController> controllers = tile.actuatorPorts.map((p) => TextEditingController(text: p)).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text("${'hardware_assignment'.tr} (${tile.type.name.toUpperCase()})"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(controllers.length, (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: TextField(controller: controllers[index], decoration: InputDecoration(labelText: "${'actuator'.tr} ${index + 1} (Port/Pin)", border: const OutlineInputBorder())),
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () {
              Map<String, TrackTile> newGrid = Map.from(widget.grid);
              TrackTile updatedTile = tile.copy();
              updatedTile.actuatorPorts = controllers.map((c) => c.text).toList();
              newGrid[key] = updatedTile;
              widget.onGridChanged(newGrid);
              Navigator.pop(context);
            },
            child: Text('save'.tr),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('stellpult'.tr),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          Row(
            children: [
              Text('bedienen'.tr),
              Switch(
                value: _configMode,
                activeColor: Colors.orange,
                onChanged: (val) => setState(() {
                  _configMode = val;
                  _activeRoute.clear(); 
                  _isRoutingMode = false;
                  _routeStart = null;
                }),
              ),
              Text('konfigurieren'.tr),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') widget.onOpenEditor();
              if (value == 'export') _exportGrid();
              if (value == 'import') _importGrid();
              if (value == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()))
                  .then((_) => widget.onSettingsRefresh()); 
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, color: Colors.white), const SizedBox(width: 8), Text('edit_trackplan'.tr)])),
              PopupMenuItem(value: 'settings', child: Row(children: [const Icon(Icons.settings, color: Colors.white), const SizedBox(width: 8), Text('settings'.tr)])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'export', child: Row(children: [const Icon(Icons.copy, color: Colors.blueAccent), const SizedBox(width: 8), Text('export_plan'.tr)])),
              PopupMenuItem(value: 'import', child: Row(children: [const Icon(Icons.download, color: Colors.greenAccent), const SizedBox(width: 8), Text('import_plan'.tr)])),
            ],
          ),
        ],
      ),
      
      // NEU: Der schwebende Action-Button unten in der Mitte
      floatingActionButton: _buildRouteFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      body: InteractiveViewer(
        transformationController: _transformationController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(3000),
        child: GestureDetector(
          onTapUp: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            key: _canvasKey,
            size: const Size(3000, 3000),
            painter: TrackPainter(
              grid: widget.grid, 
              selection: {}, 
              activeRoute: _activeRoute, 
              activeSwitchStates: _activeSwitchStates, 
              routeStart: _routeStart,  
              routeVia: _routeVia, 
              snapSize: _snapSize, tileSize: _tileSize,
              dragOffset: Offset.zero, buildPreview: [], isControlMode: true,
            ),
          ),
        ),
      ),
    );
  }
}