import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:convert';                  
import 'dart:math' as math;
import '../models/track_tile.dart';
import '../widgets/track_painter.dart';

// NEU: Das 'label' Werkzeug hinzugefügt
enum EditorTool { pan, build, pointer, delete, label }

class EditorScreen extends StatefulWidget {
  final Map<String, TrackTile> grid;
  final Function(Map<String, TrackTile>) onSaveAndExit;

  const EditorScreen({super.key, required this.grid, required this.onSaveAndExit});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late Map<String, TrackTile> _localGrid;
  Set<String> _selection = {};
  final List<Map<String, TrackTile>> _history = [];
  final List<Map<String, TrackTile>> _redoHistory = [];

  final double _snapSize = 30.0; 
  final double _tileSize = 60.0;
  TileType _selectedType = TileType.straight;
  EditorTool _activeTool = EditorTool.build;
  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();

  bool _isDraggingTiles = false;
  Offset _dragStartLocal = Offset.zero;
  Offset _dragCurrentLocal = Offset.zero;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  Offset? _buildStartGrid;
  Offset? _buildCurrentGrid;

  @override
  void initState() {
    super.initState();
    _localGrid = widget.grid.map((k, v) => MapEntry(k, v.copy()));
    _transformationController.value = Matrix4.translationValues(-1000, -1000, 0);
  }

  void _saveState() {
    _history.add(_localGrid.map((k, v) => MapEntry(k, v.copy())));
    _redoHistory.clear(); 
    if (_history.length > 50) _history.removeAt(0); 
  }

  void _undo() {
    if (_history.isNotEmpty) {
      setState(() {
        _redoHistory.add(_localGrid.map((k, v) => MapEntry(k, v.copy())));
        _localGrid = _history.removeLast().map((k, v) => MapEntry(k, v.copy()));
        _selection.clear();
      });
    }
  }

  void _redo() {
    if (_redoHistory.isNotEmpty) {
      setState(() {
        _history.add(_localGrid.map((k, v) => MapEntry(k, v.copy())));
        _localGrid = _redoHistory.removeLast().map((k, v) => MapEntry(k, v.copy()));
        _selection.clear();
      });
    }
  }

  void _exportGrid() {
    final Map<String, dynamic> exportData = _localGrid.map((k, v) => MapEntry(k, v.toJson()));
    Clipboard.setData(ClipboardData(text: jsonEncode(exportData)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kopiert!"), backgroundColor: Colors.green));
  }

  void _importGrid() {
    final TextEditingController importController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Plan importieren"),
        content: TextField(controller: importController, maxLines: 5),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Abbrechen")),
          ElevatedButton(
            onPressed: () {
              try {
                final Map<String, dynamic> decoded = jsonDecode(importController.text);
                _saveState();
                setState(() {
                  _localGrid = decoded.map((k, v) => MapEntry(k, TrackTile.fromJson(v)));
                  _selection.clear();
                });
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fehler!"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Laden"),
          )
        ],
      ),
    );
  }

void _showLabelDialog(String key, TrackTile tile) {
    TextEditingController ctrl = TextEditingController(text: tile.label);
    int selectedColor = tile.labelColor;

    // Eine kleine Auswahl an signalstarken Farben
    final List<int> colors = [
      0xFFFFFF00, // Gelb (YellowAccent)
      0xFFFFFFFF, // Weiß
      0xFFFF5252, // Rot (RedAccent)
      0xFF69F0AE, // Grün (GreenAccent)
      0xFF448AFF, // Blau (BlueAccent)
      0xFFFFAB40, // Orange (OrangeAccent)
      0xFFFF4081, // Pink (PinkAccent)
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text("Gleisnummer / Name"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(), 
                    hintText: "z.B. W1 oder Gl. 3"
                  ),
                ),
                const SizedBox(height: 16),
                const Text("Farbe wählen:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: colors.map((c) => GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = c),
                    child: Container(
                      width: 32, 
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          // Zeigt einen weißen Rand um die ausgewählte Farbe
                          color: selectedColor == c ? Colors.white : Colors.transparent,
                          width: 3,
                        )
                      ),
                    ),
                  )).toList(),
                )
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Abbrechen")),
              ElevatedButton(
                onPressed: () {
                  _saveState();
                  setState(() {
                    _localGrid[key]!.label = ctrl.text;
                    _localGrid[key]!.labelColor = selectedColor; // Sichert die neue Farbe
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Speichern"),
              )
            ]
          );
        }
      )
    );
  }

  Offset _getTransformedOffset(Offset pos) {
    final RenderBox? box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(pos) ?? pos;
  }

  String _getKey(Offset pos) => "${(pos.dx / _snapSize).round()},${(pos.dy / _snapSize).round()}";

  Rect? _getSelectionBounds() {
    if (_selection.isEmpty) return null;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (String key in _selection) {
      var parts = key.split(',');
      double px = double.parse(parts[0]) * _snapSize;
      double py = double.parse(parts[1]) * _snapSize;
      if (px < minX) minX = px;
      if (py < minY) minY = py;
      if (px > maxX) maxX = px;
      if (py > maxY) maxY = py;
    }
    double buffer = _tileSize / 2;
    return Rect.fromLTRB(minX - buffer, minY - buffer, maxX + buffer, maxY + buffer);
  }

  void _onTapUp(TapUpDetails details) {
    final pos = _getTransformedOffset(details.globalPosition);
    final key = _getKey(pos);

    // NEU: Wenn das Label-Werkzeug aktiv ist und wir ein Gleis treffen
    if (_activeTool == EditorTool.label && _localGrid.containsKey(key)) {
      _showLabelDialog(key, _localGrid[key]!);
      return;
    }

    if (_activeTool == EditorTool.delete && _localGrid.containsKey(key)) {
      _saveState(); setState(() => _localGrid.remove(key));
    } else if (_activeTool == EditorTool.build && _buildStartGrid == _buildCurrentGrid) {
      _saveState();
      setState(() {
        if (_localGrid.containsKey(key)) {
          _localGrid[key]!.rotation = (_localGrid[key]!.rotation + 1) % 8;
        } else {
          _localGrid[key] = TrackTile(type: _selectedType);
        }
      });
    } else if (_activeTool == EditorTool.pointer) {
      setState(() { 
        if (_localGrid.containsKey(key)) _selection = {key}; 
        else _selection.clear(); 
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_activeTool == EditorTool.label) return; // Beim Beschriften kein Drag!
    
    final Offset pos = _getTransformedOffset(details.globalPosition);
    
    if (_activeTool == EditorTool.build) {
      setState(() {
        _buildStartGrid = Offset((pos.dx / _snapSize).roundToDouble(), (pos.dy / _snapSize).roundToDouble());
        _buildCurrentGrid = _buildStartGrid;
      });
    } else if (_activeTool == EditorTool.pointer) {
      final String key = _getKey(pos);
      Rect? selBounds = _getSelectionBounds();
      bool inBounds = selBounds != null && selBounds.contains(pos);
      bool onTile = _localGrid.containsKey(key);

      setState(() {
        if (inBounds || (onTile && _selection.contains(key))) {
          _isDraggingTiles = true; _dragStartLocal = pos; _dragCurrentLocal = pos;
        } else if (onTile) {
          _selection = {key}; _isDraggingTiles = true; _dragStartLocal = pos; _dragCurrentLocal = pos;
        } else {
          _selection.clear(); _isDraggingTiles = false; _marqueeStart = pos; _marqueeEnd = pos;
        }
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeTool == EditorTool.label) return;
    final Offset pos = _getTransformedOffset(details.globalPosition);
    setState(() {
      if (_activeTool == EditorTool.build) {
        _buildCurrentGrid = Offset((pos.dx / _snapSize).roundToDouble(), (pos.dy / _snapSize).roundToDouble());
      } else if (_activeTool == EditorTool.pointer) {
        if (_isDraggingTiles) _dragCurrentLocal = pos; else _marqueeEnd = pos;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeTool == EditorTool.label) return;
    setState(() {
      if (_activeTool == EditorTool.build && _buildStartGrid != null) {
        var newTiles = _getBuildPreview();
        if (newTiles.isNotEmpty) {
          _saveState();
          for (var t in newTiles) { _localGrid[t.key] = t.value; }
        }
        _buildStartGrid = null; _buildCurrentGrid = null;
      } else if (_activeTool == EditorTool.pointer) {
        if (_isDraggingTiles) {
          Offset diff = _dragCurrentLocal - _dragStartLocal;
          int dxSteps = (diff.dx / _snapSize).round();
          int dySteps = (diff.dy / _snapSize).round();

          if (dxSteps != 0 || dySteps != 0) {
            _saveState();
            Map<String, TrackTile> tempGrid = Map.from(_localGrid);
            Set<String> newSelection = {};
            List<MapEntry<String, TrackTile>> movingTiles = [];
            for (String key in _selection) {
              if (tempGrid.containsKey(key)) movingTiles.add(MapEntry(key, tempGrid.remove(key)!));
            }
            for (var entry in movingTiles) {
              var parts = entry.key.split(',');
              String nKey = "${int.parse(parts[0]) + dxSteps},${int.parse(parts[1]) + dySteps}";
              tempGrid[nKey] = entry.value; newSelection.add(nKey);
            }
            _localGrid = tempGrid; _selection = newSelection;
          }
          _isDraggingTiles = false; _dragStartLocal = Offset.zero; _dragCurrentLocal = Offset.zero;
        } else if (_marqueeStart != null && _marqueeEnd != null) {
          Rect selectionRect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
          _selection.clear();
          _localGrid.forEach((key, tile) {
            var parts = key.split(',');
            if (selectionRect.contains(Offset(double.parse(parts[0]) * _snapSize, double.parse(parts[1]) * _snapSize))) {
              _selection.add(key);
            }
          });
          _marqueeStart = null; _marqueeEnd = null;
        }
      }
    });
  }

  List<MapEntry<String, TrackTile>> _getBuildPreview() {
    if (_buildStartGrid == null || _buildCurrentGrid == null) return [];
    double dx = _buildCurrentGrid!.dx - _buildStartGrid!.dx;
    double dy = _buildCurrentGrid!.dy - _buildStartGrid!.dy;
    if (dx == 0 && dy == 0) return [];

    double angle = math.atan2(dy, dx);
    int octant = ((angle / (math.pi / 4)).round() + 8) % 8;

    int stepX = 0, stepY = 0;
    switch (octant) {
      case 0: stepX = 2; stepY = 0; break;
      case 1: stepX = 2; stepY = 2; break;
      case 2: stepX = 0; stepY = 2; break;
      case 3: stepX = -2; stepY = 2; break;
      case 4: stepX = -2; stepY = 0; break;
      case 5: stepX = -2; stepY = -2; break;
      case 6: stepX = 0; stepY = -2; break;
      case 7: stepX = 2; stepY = -2; break;
    }

    int rotation = octant;
    List<MapEntry<String, TrackTile>> tiles = [];

    if (_selectedType == TileType.halfStraight) {
      stepX ~/= 2; stepY ~/= 2;
      int nTiles = (stepX != 0) ? (dx / stepX).abs().round() : (dy / stepY).abs().round();
      for (int i = 0; i < nTiles; i++) {
        tiles.add(MapEntry("${_buildStartGrid!.dx.toInt() + (i + 1) * stepX},${_buildStartGrid!.dy.toInt() + (i + 1) * stepY}", TrackTile(type: _selectedType, rotation: rotation)));
      }
    } else {
      int nTiles = (stepX != 0) ? (dx / stepX).abs().round() : (dy / stepY).abs().round();
      for (int i = 0; i < nTiles; i++) {
        tiles.add(MapEntry("${_buildStartGrid!.dx.toInt() + i * stepX + (stepX ~/ 2)},${_buildStartGrid!.dy.toInt() + i * stepY + (stepY ~/ 2)}", TrackTile(type: _selectedType, rotation: rotation)));
      }
    }
    return tiles;
  }

  String _getTileName(TileType type) {
    switch (type) {
      case TileType.straight: return "Schiene";
      case TileType.halfStraight: return "1/2 Schiene";
      case TileType.switchLeft: return "Weiche L";
      case TileType.switchRight: return "Weiche R";
      case TileType.crossing: return "Kreuzung";
      case TileType.doubleSlip: return "DKW";
      case TileType.threeWay: return "3-Wege";
      case TileType.buffer: return "Prellbock";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gleisbau-Editor"),
        backgroundColor: Colors.grey[900],
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _history.isNotEmpty ? _undo : null),
          IconButton(icon: const Icon(Icons.redo), onPressed: _redoHistory.isNotEmpty ? _redo : null),
          const VerticalDivider(width: 20, color: Colors.grey),
          IconButton(icon: Icon(Icons.pan_tool, color: _activeTool == EditorTool.pan ? Colors.blue : Colors.white), onPressed: () => setState(() => _activeTool = EditorTool.pan)),
          IconButton(icon: Icon(Icons.edit, color: _activeTool == EditorTool.build ? Colors.blue : Colors.white), onPressed: () => setState(() => _activeTool = EditorTool.build)),
          IconButton(icon: Icon(Icons.highlight_alt, color: _activeTool == EditorTool.pointer ? Colors.blue : Colors.white), onPressed: () => setState(() => _activeTool = EditorTool.pointer)),
          
          // NEU: Der Beschriftungs-Button (Label Tool)
          IconButton(icon: Icon(Icons.label, color: _activeTool == EditorTool.label ? Colors.yellowAccent : Colors.white), onPressed: () => setState(() => _activeTool = EditorTool.label)),
          
          IconButton(
            icon: Icon(Icons.delete, color: _activeTool == EditorTool.delete ? Colors.red : Colors.white),
            onPressed: () {
              if (_selection.isNotEmpty) {
                _saveState();
                setState(() { for (var k in _selection) _localGrid.remove(k); _selection.clear(); });
              } else setState(() => _activeTool = EditorTool.delete);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'exit') widget.onSaveAndExit(_localGrid);
              if (value == 'export') _exportGrid();
              if (value == 'import') _importGrid();
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.copy, color: Colors.blueAccent), SizedBox(width: 8), Text("Plan exportieren")])),
              const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.download, color: Colors.greenAccent), SizedBox(width: 8), Text("Plan importieren")])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'exit', child: Row(children: [Icon(Icons.check_circle, color: Colors.greenAccent), SizedBox(width: 8), Text("Gleisbau beenden")])),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              color: Colors.grey[900], padding: const EdgeInsets.all(8),
              child: Row(
                children: TileType.values.map((type) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ChoiceChip(
                    label: Text(_getTileName(type)),
                    selected: _selectedType == type && _activeTool == EditorTool.build,
                    onSelected: (val) => setState(() { _selectedType = type; _activeTool = EditorTool.build; }),
                  ),
                )).toList(),
              ),
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(3000),
              panEnabled: _activeTool == EditorTool.pan,
              child: GestureDetector(
                onTapUp: _activeTool == EditorTool.pan ? null : _onTapUp, 
                onPanStart: _activeTool == EditorTool.pan ? null : _onPanStart, 
                onPanUpdate: _activeTool == EditorTool.pan ? null : _onPanUpdate, 
                onPanEnd: _activeTool == EditorTool.pan ? null : _onPanEnd,
                behavior: HitTestBehavior.opaque,
                child: CustomPaint(
                  key: _canvasKey, size: const Size(3000, 3000),
                  painter: TrackPainter(
                    grid: _localGrid, selection: _selection, snapSize: _snapSize, tileSize: _tileSize,
                    dragOffset: _isDraggingTiles ? (_dragCurrentLocal - _dragStartLocal) : Offset.zero, 
                    marqueeStart: _marqueeStart, marqueeEnd: _marqueeEnd, buildPreview: _getBuildPreview(), isControlMode: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}