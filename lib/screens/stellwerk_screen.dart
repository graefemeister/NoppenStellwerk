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
  Set<String> _activeRoute = {}; // Die aktuell leuchtende Fahrstraße

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.translationValues(-1000, -1000, 0);
  }

  void _handleTap(TapUpDetails details) {
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final pos = box?.globalToLocal(details.globalPosition) ?? details.globalPosition;
    final String key = "${(pos.dx / _snapSize).round()},${(pos.dy / _snapSize).round()}";

    if (!widget.grid.containsKey(key)) return;
    TrackTile tile = widget.grid[key]!;

    // 1. Konfigurations-Modus
    if (_configMode) {
      if (tile.isSwitch) _showConfigDialog(key, tile);
      return;
    }

    // 2. Fahrstraßen-Stell-Modus (Start-Ziel)
    if (_isRoutingMode) {
      setState(() {
        if (_routeStart == null) {
          _routeStart = key; // Startpunkt gesetzt
        } else if (_routeStart == key) {
          _routeStart = null; // Klick auf sich selbst hebt Startpunkt auf
        } else {
          _calculateAndSetRoute(_routeStart!, key); // Ziel gewählt -> Berechnen!
        }
      });
      return;
    }

    // 3. Normaler manueller Modus (Einzelweichen stellen)
    if (!tile.isSwitch) return;

    // FAHRSTRASSENVERSCHLUSS: Verhindert manuelles Schalten von Weichen in aktiver Route
    if (_activeRoute.contains(key)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Verschluss! Weiche ist in Fahrstraße gesperrt."), 
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Wenn nicht gesperrt, normal umstellen
    _cycleSwitchState(key, tile);
  }

  void _calculateAndSetRoute(String start, String target) {
    RouteResult? result = PathfindingService.findRoute(widget.grid, start, target);

    if (result != null) {
      Map<String, TrackTile> newGrid = Map.from(widget.grid);
      
      // Schalte die Weichen in die errechnete Richtung
      result.requiredSwitchStates.forEach((switchKey, newState) {
        TrackTile updatedSwitch = newGrid[switchKey]!.copy();
        updatedSwitch.switchState = newState;
        newGrid[switchKey] = updatedSwitch;
      });

      widget.onGridChanged(newGrid);

      setState(() {
        _activeRoute = result.pathKeys.toSet();
        _isRoutingMode = false; // Modus beenden
        _routeStart = null;
      });
      
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kein physikalischer Weg gefunden!"), backgroundColor: Colors.redAccent),
      );
      setState(() {
        _routeStart = null; // Startpunkt zurücksetzen, aber im Modus bleiben
      });
    }
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

  // --- HILFS-WIDGET: Der dynamische Fahrstraßen-Button ---
  Widget _buildRouteFab() {
    // Zustand 1: Fahrstraße ist aktiv -> Knopf wird ROT (Auflösen)
    if (_activeRoute.isNotEmpty) {
      return FloatingActionButton.extended(
        onPressed: () => setState(() {
          _activeRoute.clear();
          _routeStart = null;
          _isRoutingMode = false;
        }),
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.clear, color: Colors.white),
        label: const Text("Fahrstraße auflösen", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    }

    // Zustand 2: Wir sind mitten in der Start-Ziel-Auswahl -> Knopf wird ORANGE (Abbrechen)
    if (_isRoutingMode) {
       return FloatingActionButton.extended(
        onPressed: () => setState(() {
          _isRoutingMode = false;
          _routeStart = null;
        }),
        backgroundColor: Colors.orangeAccent,
        icon: const Icon(Icons.close, color: Colors.black),
        label: Text(
          _routeStart == null ? "Start wählen... (Abbrechen)" : "Ziel wählen... (Abbrechen)", 
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
      );
    }

    // Zustand 3: Normaler Betrieb -> Knopf ist GELB (Fahrstraße stellen)
    return FloatingActionButton.extended(
      onPressed: () => setState(() {
        _isRoutingMode = true;
        _routeStart = null;
      }),
      backgroundColor: Colors.yellowAccent,
      icon: const Icon(Icons.route, color: Colors.black),
      label: const Text("Fahrstraße stellen", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
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
              routeStart: _routeStart,   
              snapSize: _snapSize, tileSize: _tileSize,
              dragOffset: Offset.zero, buildPreview: [], isControlMode: true,
            ),
          ),
        ),
      ),
    );
  }
}