enum TileType { straight, halfStraight, switchLeft, switchRight, crossing, doubleSlip, threeWay, buffer }

class TrackTile {
  TileType type;
  int rotation; 
  int switchState; 
  List<String> actuatorPorts; 
  String label; 
  int labelColor;

  TrackTile({
    required this.type, 
    this.rotation = 0, 
    this.switchState = 0,
    List<String>? actuatorPorts,
    this.label = "",
    this.labelColor = 0xFFFFFF00,
  }) : actuatorPorts = actuatorPorts ?? _initPorts(type);

  static List<String> _initPorts(TileType type) {
    if (type == TileType.switchLeft || type == TileType.switchRight) return [""];
    if (type == TileType.threeWay) return ["", ""];
    if (type == TileType.doubleSlip) return ["", "", "", ""];
    return [];
  }

  TrackTile copy() => TrackTile(
    type: type, 
    rotation: rotation, 
    switchState: switchState, 
    actuatorPorts: List.from(actuatorPorts),
    label: label,
    labelColor: labelColor,
  );

  TrackTile copyWith({
    TileType? type,
    int? rotation,
    int? switchState,
    List<String>? actuatorPorts,
    String? label,
    int? labelColor,
  }) {
    return TrackTile(
      type: type ?? this.type,
      rotation: rotation ?? this.rotation,
      switchState: switchState ?? this.switchState,
      actuatorPorts: actuatorPorts ?? this.actuatorPorts,
      label: label ?? this.label,
      labelColor: labelColor ?? this.labelColor,
    );
  }

  bool get isSwitch => actuatorPorts.isNotEmpty;

  // NEU: Wandelt die Kachel in ein Map-Format um
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'rotation': rotation,
      'switchState': switchState,
      'actuatorPorts': actuatorPorts,
      'label': label,
      'labelColor': labelColor,
    };
  }

  // NEU: Baut die Kachel aus einer Map wieder auf
  factory TrackTile.fromJson(Map<String, dynamic> json) {
    return TrackTile(
      type: TileType.values.byName(json['type']),
      rotation: json['rotation'] ?? 0,
      switchState: json['switchState'] ?? 0,
      actuatorPorts: List<String>.from(json['actuatorPorts'] ?? []),
      label: json['label'] ?? "",
      labelColor: json['labelColor'] ?? 0xFFFFFF00,
    );
  }
}

