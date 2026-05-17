import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/track_tile.dart';

class TrackPainter extends CustomPainter {
  final Map<String, TrackTile> grid;
  final Set<String> selection;
  final Set<String> activeRoute; // NEU: Die aktive Fahrstraße
  final String? routeStart;      // NEU: Der markierte Startpunkt
  final double snapSize, tileSize;
  final Offset dragOffset;
  final Offset? marqueeStart, marqueeEnd;
  final List<MapEntry<String, TrackTile>> buildPreview;
  final bool isControlMode; 

  TrackPainter({
    required this.grid, required this.selection, 
    this.activeRoute = const {}, this.routeStart, // Initialisierung
    required this.snapSize, required this.tileSize,
    required this.dragOffset, this.marqueeStart, this.marqueeEnd, required this.buildPreview,
    this.isControlMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF161616));
    
    final pLight = Paint()..color = Colors.white.withOpacity(0.04);
    final pBold = Paint()..color = Colors.white.withOpacity(0.12);
    for (double i = 0; i < size.width; i += snapSize) {
      for (double j = 0; j < size.height; j += snapSize) {
        bool isFullGrid = (i % tileSize == 0) && (j % tileSize == 0);
        canvas.drawCircle(Offset(i, j), isFullGrid ? 2 : 1, isFullGrid ? pBold : pLight);
      }
    }

    bool hasActiveRoute = activeRoute.isNotEmpty;

    // Die Standard-Stifte
    final paintBase = Paint()..color = Colors.white..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final paintDimmed = Paint()..color = Colors.white.withOpacity(0.15)..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    
    // NEU: Der leuchtende Stift für die aktive Fahrstraße (SpDrS60 Gelb)
    final paintRoute = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4.0); // Der Glow-Effekt!

    // NEU: Der Stift für restliche Gleise, wenn eine Fahrstraße aktiv ist (Ausgrauen)
    final paintBackground = Paint()..color = Colors.white.withOpacity(0.1)..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;

    double snapDx = (dragOffset.dx / snapSize).round() * snapSize;
    double snapDy = (dragOffset.dy / snapSize).round() * snapSize;
    Offset snappedDrag = Offset(snapDx, snapDy);

    // Alle Gleise zeichnen
    grid.forEach((key, tile) {
      if (!selection.contains(key)) {
        Paint activePaint = paintBase;
        
        if (hasActiveRoute) {
          activePaint = activeRoute.contains(key) ? paintRoute : paintBackground;
        }

        _drawTileAt(canvas, key, tile, activePaint, paintDimmed, Offset.zero);

        // Markiert den Startpunkt der Route grün leuchtend
        if (key == routeStart && !hasActiveRoute) {
          final coords = key.split(",");
          canvas.drawCircle(
            Offset(double.parse(coords[0]) * snapSize, double.parse(coords[1]) * snapSize), 
            15, 
            Paint()..color = Colors.greenAccent.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          );
        }
      }
    });

// --- FEHLTE: 1. Ausgewählte Gleise beim Verschieben (Pan) zeichnen ---
    final paintSelected = Paint()..color = Colors.blueAccent..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (String key in selection) {
      if (grid.containsKey(key)) {
        _drawTileAt(canvas, key, grid[key]!, paintSelected, paintDimmed, snappedDrag);
      }
    }

    // --- FEHLTE: 2. Die grüne Vorschau beim Bauen neuer Gleise zeichnen ---
    final paintPreview = Paint()..color = Colors.greenAccent.withOpacity(0.6)..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (var entry in buildPreview) {
      _drawTileAt(canvas, entry.key, entry.value, paintPreview, paintDimmed, Offset.zero);
    }

    // ... [Hier kommt dann dein Block, der die Text-Labels zeichnet] ...    
    // (Auszug für die Labels, damit sie weiterleben:)
    grid.forEach((key, tile) {
      if (tile.label.isNotEmpty) {
        final coords = key.split(",");
        final double x = double.parse(coords[0]) * snapSize;
        final double y = double.parse(coords[1]) * snapSize;
        
        // Dimmt den Text ab, wenn er nicht zur Fahrstraße gehört
        double opacity = (hasActiveRoute && !activeRoute.contains(key)) ? 0.3 : 1.0;

        final textSpan = TextSpan(
          text: tile.label,
          style: TextStyle(
            color: Color(tile.labelColor).withOpacity(opacity), 
            fontSize: 12, 
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54.withOpacity(opacity), 
          ),
        );
        final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(x + snappedDrag.dx + 5, y + snappedDrag.dy - 18));
      }
    });
  }

  void _drawTileAt(Canvas canvas, String key, TrackTile tile, Paint active, Paint inactive, Offset offset) {
    final coords = key.split(",");
    final double x = double.parse(coords[0]) * snapSize;
    final double y = double.parse(coords[1]) * snapSize;

    canvas.save();
    canvas.translate(x + offset.dx, y + offset.dy);
    canvas.rotate(tile.rotation * math.pi / 4);
    _drawGeometry(canvas, tile.type, tile.switchState, active, inactive, tile.rotation % 2 != 0);
    canvas.restore();
  }

  void _drawGeometry(Canvas canvas, TileType type, int state, Paint active, Paint inactive, bool isDiag) {
    final double h = tileSize / 2; 
    final double currentH = isDiag ? h * math.sqrt(2) : h;
    Paint p(int requiredState) => (!isControlMode || state == requiredState) ? active : inactive;
    Paint pAlways = active;

    switch (type) {
      case TileType.straight: canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), pAlways); break;
      case TileType.halfStraight: canvas.drawLine(Offset(-currentH, 0), const Offset(0, 0), pAlways); break;
      case TileType.crossing:
        canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), pAlways);
        canvas.drawLine(Offset(0, -currentH), Offset(0, currentH), pAlways);
        break;
      case TileType.switchLeft:
        canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), p(0)); 
        canvas.drawLine(Offset(-currentH, 0), Offset(0, -currentH), p(1)); 
        break;
      case TileType.switchRight:
        canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), p(0));
        canvas.drawLine(Offset(-currentH, 0), Offset(0, currentH), p(1));
        break;
      case TileType.threeWay:
        canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), p(0)); 
        canvas.drawLine(Offset(-currentH, 0), Offset(0, -currentH), p(1)); 
        canvas.drawLine(Offset(-currentH, 0), Offset(0, currentH), p(2)); 
        break;
      case TileType.doubleSlip:
        canvas.drawLine(Offset(-currentH, 0), Offset(currentH, 0), p(0)); 
        canvas.drawLine(Offset(0, -currentH), Offset(0, currentH), p(1)); 
        canvas.drawLine(Offset(-currentH, 0), Offset(0, currentH), p(2)); 
        canvas.drawLine(Offset(currentH, 0), Offset(0, -currentH), p(3)); 
        break;
      case TileType.buffer:
        canvas.drawLine(Offset(-currentH, 0), const Offset(0, 0), pAlways);
        canvas.drawLine(Offset(0, -tileSize/6), Offset(0, tileSize/6), pAlways);
        break;
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}