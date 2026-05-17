import 'package:flutter/material.dart';
import '../settings_manager.dart';
import '../localization.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _currentScale = 1.0;
  bool _isAutoScale = true;
  int _currentTheme = 0; 
  bool _wakelock = false;
  String _currentLang = 'de';

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  void _loadAllSettings() async {
    final scale = await SettingsManager.loadScale();
    final autoScale = await SettingsManager.loadAutoScale();
    final theme = await SettingsManager.loadTheme();
    final wake = await SettingsManager.loadWakelock();
    final lang = await SettingsManager.loadLanguage();
    
    setState(() {
      _currentScale = scale;
      _isAutoScale = autoScale;
      _currentTheme = theme;
      _wakelock = wake;
      _currentLang = lang;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Text('settings'.tr),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- SPRACHE ---
            Card(
              child: ListTile(
                leading: Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
                title: const Text("Language / Sprache", style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: DropdownButton<String>(
                  value: _currentLang,
                  underline: const SizedBox(),
                  onChanged: (String? newValue) async {
                    if (newValue != null) {
                      await SettingsManager.saveLanguage(newValue);
                      L10n.lang = newValue; 
                      setState(() => _currentLang = newValue);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('lang_changed'.tr)),
                      );
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'de', child: Text("Deutsch")),
                    DropdownMenuItem(value: 'en', child: Text("English")),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // --- SKALIERUNG ---
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(Icons.autorenew, color: Theme.of(context).colorScheme.primary),
                    title: Text('ui_auto_scale'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('ui_auto_scale_desc'.tr, style: const TextStyle(fontSize: 12)),
                    value: _isAutoScale,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) async {
                      setState(() => _isAutoScale = val);
                      await SettingsManager.saveAutoScale(val); 
                      if (val) {
                        setState(() => _currentScale = 1.0);
                        await SettingsManager.saveScale(1.0);
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(Icons.format_size, color: _isAutoScale ? Colors.grey : Theme.of(context).colorScheme.primary),
                    title: Text('ui_scaling_manual'.tr, style: TextStyle(color: _isAutoScale ? Colors.grey : null)),
                    subtitle: Text(_isAutoScale ? "Auto" : "${(_currentScale * 100).toInt()}%"),
                  ),
                  Opacity(
                    opacity: _isAutoScale ? 0.3 : 1.0,
                    child: IgnorePointer(
                      ignoring: _isAutoScale,
                      child: Slider(
                        value: _currentScale,
                        min: 0.5,
                        max: 1.5,
                        divisions: 10,
                        activeColor: Theme.of(context).colorScheme.primary,
                        onChanged: (val) async {
                          setState(() => _currentScale = val);
                          await SettingsManager.saveScale(val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // --- WAKELOCK (Bildschirm anlassen) ---
            Card(
              child: SwitchListTile(
                secondary: Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                title: Text('display_always_on'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('display_always_on_desc'.tr, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                value: _wakelock,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (val) async {
                  setState(() => _wakelock = val);
                  await SettingsManager.saveWakelock(val);
                  await SettingsManager.setWakelock(val);
                },
              ),
            ),
            const SizedBox(height: 12),

            // --- DESIGN / THEME ---
            Card(
              child: ListTile(
                leading: Icon(Icons.brightness_6, color: Theme.of(context).colorScheme.primary),
                title: Text('design_theme'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: DropdownButton<int>(
                  value: _currentTheme,
                  underline: const SizedBox(),
                  onChanged: (val) async {
                    if (val != null) {
                      setState(() => _currentTheme = val);
                      await SettingsManager.saveTheme(val);
                    }
                  },
                  items: [
                    DropdownMenuItem(value: 0, child: Text('theme_system'.tr)),
                    DropdownMenuItem(value: 1, child: Text('theme_light'.tr)),
                    DropdownMenuItem(value: 2, child: Text('theme_dark'.tr)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}