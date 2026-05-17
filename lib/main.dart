import 'package:flutter/material.dart';
import 'models/track_tile.dart';
import 'screens/stellwerk_screen.dart';
import 'screens/editor_screen.dart';
import 'settings_manager.dart'; 
import 'localization.dart';     

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final wake = await SettingsManager.loadWakelock();
  await SettingsManager.setWakelock(wake);
  runApp(const NoppenstellwerkApp());
}

class NoppenstellwerkApp extends StatefulWidget {
  const NoppenstellwerkApp({super.key});

  @override
  State<NoppenstellwerkApp> createState() => _NoppenstellwerkAppState();
}

class _NoppenstellwerkAppState extends State<NoppenstellwerkApp> {
  ThemeMode _themeMode = ThemeMode.system;
  double _scaleFactor = 1.0;

  @override
  void initState() {
    super.initState();
    _refreshSettings();
  }

  void _refreshSettings() async {
    final themeInt = await SettingsManager.loadTheme();
    final lang = await SettingsManager.loadLanguage();
    final scale = await SettingsManager.loadScale();

    L10n.lang = lang;

    setState(() {
      _scaleFactor = scale;
      if (themeInt == 1) {
        _themeMode = ThemeMode.light;
      } else if (themeInt == 2) {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
      ),
      themeMode: _themeMode,
      home: Builder(
        builder: (context) {
          return Transform.scale(
            scale: _scaleFactor,
            alignment: Alignment.center,
            child: MainScreen(onSettingsChanged: _refreshSettings),
          );
        }
      ),
    );
  }
}

enum AppMode { stellwerk, editor }

class MainScreen extends StatefulWidget {
  final VoidCallback onSettingsChanged;
  const MainScreen({super.key, required this.onSettingsChanged});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, TrackTile> _globalGrid = {};
  AppMode _currentMode = AppMode.stellwerk; 

  @override
  Widget build(BuildContext context) {
    if (_currentMode == AppMode.editor) {
      return EditorScreen(
        grid: _globalGrid,
        onSaveAndExit: (updatedGrid) {
          setState(() {
            _globalGrid = updatedGrid;
            _currentMode = AppMode.stellwerk; 
          });
        },
      );
    } else {
      return StellwerkScreen(
        grid: _globalGrid,
        onGridChanged: (updatedGrid) => setState(() => _globalGrid = updatedGrid),
        onOpenEditor: () => setState(() => _currentMode = AppMode.editor),
        onSettingsRefresh: widget.onSettingsChanged,
      );
    }
  }
}