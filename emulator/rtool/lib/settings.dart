import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const String _MANAGER_HOST_KEY = "managerHost";
  static const String _MANAGER_PORT_KEY = "managerPort";
  static const String _TOOL_ID_KEY = "toolId";
  static const String _SENSITIVITY_RANGE_KEY = "sensitivityRange";

  String managerHost;
  int managerPort;
  int toolId;
  int sensitivityRange;


  Settings(this.managerHost, this.managerPort, this.toolId, this.sensitivityRange);

  Future load() async {
    print("Loading...");
    SharedPreferences prefs = await SharedPreferences.getInstance();
    this.managerHost = prefs.getString(_MANAGER_HOST_KEY) ?? "147.251.253.243";
    this.managerPort = prefs.getInt(_MANAGER_PORT_KEY) ?? 6644;
    this.toolId = prefs.getInt(_TOOL_ID_KEY) ?? 128;
    this.sensitivityRange = prefs.getInt(_SENSITIVITY_RANGE_KEY) ?? 100.0;
    print("Loaded.");
  }

  Future<Null> save() async {
    print("Saving...");
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(_MANAGER_HOST_KEY, managerHost);
    prefs.setInt(_MANAGER_PORT_KEY, managerPort);
    prefs.setInt(_TOOL_ID_KEY, toolId);
    prefs.setInt(_SENSITIVITY_RANGE_KEY, sensitivityRange);
    await prefs.commit();
    print("Saved.");
  }

  @override
  String toString() {
    return 'Settings{managerHost: $managerHost, managerPort: $managerPort, toolId: $toolId, sensitivityRange: $sensitivityRange}';
  }


}