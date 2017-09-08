import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'package:url_launcher/url_launcher.dart';
import 'messages.dart';
import 'settings.dart';

void main() {
  runApp(new RToolApp());
}

class RToolApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: "RTool",
      home: new MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  State createState() => new MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  static const STATUS_BROADCAST_TIMEOUT = const Duration(seconds: 5);
  static const VIBRATION_IDLE_TIMEOUT = const Duration(seconds: 1);
  static const VIBRATION_LENGTH = 100;
  static const MAX_VIBRATION_INTERVAL = 2000;

  final TextEditingController _managerHostController = new TextEditingController();
  final TextEditingController _managerPortController = new TextEditingController();
  final TextEditingController _toolIdController = new TextEditingController();
  final ScrollController _messagesScrollController = new ScrollController();

  Settings _settings = new Settings("0.0.0.0", 0, 0, 1);

  final int _bufferSize = 30;
  List<Text> _messages = <Text>[];
  int _startIndex = 0;

  static const MethodChannel platform = const MethodChannel("cernobor");
  bool vibrating = false;
  bool sounding = false;

  bool _running = false;
  Socket _socket;
  Location _location = new Location();
  Map<String, double> _currentLocation;
  StreamSubscription<Map<String, double>> _locationSubscription;
  Timer _statusTimer;
  Duration _vibrationInterval;
  String _nearestPowerSpotName;
  double _nearestPowerSpotDistance;
  double _nearestPowerSpotRssi;
  double _intensity;
  double _dBmThreshold;
  double _dBmTolerance = -25.0;


  MainScreenState() {
    _settings.load().then((_) {
      setState(() {
        _managerHostController.text = _settings.managerHost;
        _managerPortController.text = _settings.managerPort.toString();
        _toolIdController.text = _settings.toolId.toString();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    Scaffold scaffold = new Scaffold(
      appBar: new AppBar(title: new Text("RTool")),
      drawer: new Drawer(
        elevation: 16.0,
        child: new ListView(
          padding: new EdgeInsets.only(top: statusBarHeight),
          children: <Widget>[
            new ListTile(
              leading: new Icon(Icons.settings),
              title: new Text("Settings:"),
              onTap: null,
            ),
            new TextField(
              controller: _managerHostController,
              decoration: new InputDecoration.collapsed(
                  hintText: "server hostname"
              ),
            ),
            new TextField(
              controller: _managerPortController,
              decoration: new InputDecoration.collapsed(
                  hintText: "server port"
              ),
              inputFormatters: [
                WhitelistingTextInputFormatter.digitsOnly
              ],
              keyboardType: TextInputType.number,
              autocorrect: false,
            ),
            new TextField(
              controller: _toolIdController,
              decoration: new InputDecoration.collapsed(
                  hintText: "tool ID"
              ),
              inputFormatters: [
                WhitelistingTextInputFormatter.digitsOnly
              ],
              keyboardType: TextInputType.number,
              autocorrect: false,
            ),
            new Text("Range: ${_settings.sensitivityRange} m"),
            new Slider(
              value: _settings.sensitivityRange.toDouble(),
              min: 1.0,
              max: 500.0,
              activeColor: Theme.of(context).errorColor,
              onChanged: (double val) {
                setState(() {
                  _settings.sensitivityRange = val.round();
                });
              }
            ),
            new ListTile(
              title: new Text(_running ? "Stop" : "Start"),
              onTap: () {
                _toggleRunning();
                _handleStartStop();
                if (_running) {
                  Navigator.pop(context);
                }
              },
              leading: new Icon(_running ? Icons.pause : Icons.play_arrow),
            ),
            new RaisedButton(
                child: new Text("Open spot editor (web)"),
                onPressed: () async {
                  String url = "http://${_settings.managerHost}:8080";
                  if (await canLaunch(url)) {
                    await launch(url);
                  } else {
                    showDialog<Null>(
                        context: context,
                        child: new AlertDialog(
                          title: new Text("Cannot open URL!"),
                          content: new Text(url),
                          actions: <Widget>[
                            new FlatButton(
                              child: new Text("OK"),
                              onPressed: () {
                                Navigator.of(context).pop();
                              }
                            ),
                          ]
                        ),
                        barrierDismissible: true,
                    );
                  }
                }
            ),/*
            new ListTile(
              title: new Text('start/stop vibration'),
              onTap: () {
                setState(() {
                  if (vibrating) {
                    _vibrationInterval = null;
                  } else {
                    _vibrationInterval = new Duration(milliseconds: 100);
                  }
                  vibrating = !vibrating;
                });
              },
            ),
            new ListTile(
              title: new Text('start/stop sound'),
              onTap: () {
                if (sounding) {
                  _stopSound();
                } else {
                  _playFrequency(6000);
                }
                sounding = !sounding;
              },
            )*/
          ],
        ),
      ),
      body: new Column(
        children: <Widget>[
          new Text("Nearest power spot name: $_nearestPowerSpotName"),
          new Text("Nearest power spot distance: ${_nearestPowerSpotDistance?.toStringAsFixed(3)} m"),
          new Text("Nearest power spot RSSI: ${_nearestPowerSpotRssi?.toStringAsFixed(3)} dBm"),
          new Text("dBm threshold: ${_dBmThreshold?.toStringAsFixed(3)}, dBm tolerance: ${_dBmTolerance?.toStringAsFixed(3)}"),
          new Text("Intensity: ${_intensity?.toStringAsFixed(3)}"),
          new Text("Vibration interval: ${_vibrationInterval?.inMilliseconds ?? "-"}"),
          new Text("lat: ${_currentLocation == null ? "-" : _currentLocation["latitude"]}, lon: ${_currentLocation == null ? "-" : _currentLocation["longitude"]}"),
          new Row(
            children: <Widget>[
              new RaisedButton(
                onPressed: () => setState(_clearLogMessages),
                color: Theme.of(context).buttonColor,
                child: new Text("Clear output"),
              ),
              new RaisedButton(
                onPressed: _ping,
                color: Theme.of(context).buttonColor,
                child: new Text("Ping"),
              ),
            ],
          ),
          new Divider(height: 1.0, color: Theme.of(context).dividerColor,),
          new Flexible(
            child: new ListView.builder(
              padding: new EdgeInsets.only(bottom: 5.0),
              reverse: true,
              itemBuilder: (_, int index) => _getLogMessage(index),
              itemCount: min(_bufferSize, _messages.length),
              controller: _messagesScrollController,
            )
          )
        ]
      )
    );

    return scaffold;
  }


  @override
  void initState() {
    super.initState();
    initPlatformState();
    _locationSubscription = _location.onLocationChanged.listen((Map<String,double> result) {
      print("Acquired location: $result");
      setState(() {
        _currentLocation = result;
      });
    });

    new Timer(VIBRATION_IDLE_TIMEOUT, _vibrationTimer);
  }

  Future initPlatformState() async {
    Map<String, double> location;

    try {
      location = await _location.getLocation;
    } on PlatformException catch (e) {
      print(e);
      location = null;
    }

    if (!mounted) {
      return;
    }

    print("Retrieved initial location: $location");
    setState(() {
      _currentLocation = location;
    });
  }

  void _saveSettings() {
    _settings.managerHost = _managerHostController.text;
    _settings.managerPort = int.parse(_managerPortController.text);
    _settings.toolId = int.parse(_toolIdController.text);
    _settings.save();
  }

  void _toggleRunning() {
    setState(() {
      print("Toggling running: $_running -> ${!_running}");
      _running = !_running;
    });
  }

  void _handleStartStop() {
    _addLogMessage(_running ? "Started." : "Stopped.");
    if (_running) {
      _saveSettings();
      Socket.connect(_settings.managerHost, _settings.managerPort)
        .then((socket) {
          setState(() => _addLogMessage("Connected!"));
          _socket = socket;
          _socket.listen(
            (List<int> data) {
              String message = UTF8.decode(data);
              _handleMessage(message);
            },
            onDone: () {
              _addLogMessage("Disconnected!");
              _toggleRunning();
              _handleStartStop();
            }
          );
          _statusTimer = new Timer.periodic(STATUS_BROADCAST_TIMEOUT, (_) {
            print("broadcasting status");
            _statusBroadcast();
          });
        })
        .catchError((e) {
          setState(() {
            _addLogMessage("Could not connect: $e");
          });
          _toggleRunning();
          _handleStartStop();
        });
    } else {
      if (_socket != null) {
        _socket.destroy();
      }
      _socket = null;
      if (_statusTimer != null) {
        _statusTimer.cancel();
      }
      _vibrationInterval = null;
      print("Vibration interval: $_vibrationInterval");
      _stopVibrate();
      _stopSound();
    }
  }

  double _mapDbmToIntensity(double dBm, double dBmTolerance, double dBmThreshold) {
    return sqrt(dBm / (dBmTolerance - dBmThreshold) - dBmThreshold / (dBmTolerance - dBmThreshold));
  }

  void _handleMessage(String message) {
    var msg = JSON.decode(message);
    print("Handling message: $msg");
    setState(() {
      if (IncomingMessage.POWER_SPOT_RSSI.getTypeName() == msg["type"]) {
        double dBm = msg["dBm"];
        _dBmThreshold = msg["dBm-threshold"];
        if (dBm > _dBmThreshold) {
          _intensity = _mapDbmToIntensity(dBm, _dBmTolerance, _dBmThreshold);
          int interval = (MAX_VIBRATION_INTERVAL * (1 - _intensity)).round();
          print("In threshold - intensity: $_intensity interval: $interval");
          _vibrationInterval = new Duration(milliseconds: interval);
          _nearestPowerSpotName = msg["name"];
          _nearestPowerSpotDistance = msg["distance"];
          _nearestPowerSpotRssi = dBm;
        } else {
          _vibrationInterval = null;
          _nearestPowerSpotName = null;
          _nearestPowerSpotDistance = null;
          _nearestPowerSpotRssi = null;
        }
      } else if (IncomingMessage.PONG.getTypeName() == msg["type"]) {
        _addLogMessage(msg.toString());
      }
    });
  }

  String _getId() {
    return _toolIdController.text;
  }

  Future<Null> _playFrequency(int frequency, [int duration]) async {
    Map<String, Object> params = <String, Object>{"frequency": frequency};
    if (duration != null) {
      print("Trying to play $frequency Hz for $duration ms");
      params["duration"] = duration;
    } else {
      print("Trying to play $frequency Hz indefinitely");
    }
    try {
      await platform.invokeMethod("playFrequency", params);
    } on PlatformException catch (e) {
      print(e);
    }
  }

  Future<Null> _stopSound() async {
    print("Stopping sound");
    try {
      await platform.invokeMethod("stopSound");
    } on PlatformException catch (e) {
      print(e);
    }
  }

  Future<Null> _vibrate(int duration) async {
    Map<String, Object> params = <String, Object>{"duration": duration};
    print("Trying to vibrate for $duration ms");
    try {
      await platform.invokeMethod("vibrate", params);
    } on PlatformException catch (e) {
      print(e);
    }
  }

  Future<Null> _stopVibrate() async {
    print("Stopping vibration");
    try {
      await platform.invokeMethod("stopVibrate");
    } on PlatformException catch (e) {
      print(e);
    }
  }

  void _ping() {
    if (_socket == null) {
      _addLogMessage("Not connected!");
      return;
    }
    new PingMessage(_getId()).send(_socket);
  }

  void _statusBroadcast() {
    try {
      if (_currentLocation.containsKey("latitude") && _currentLocation.containsKey("latitude")) {
        new StatusBroadcastMessage(_getId(), _currentLocation["latitude"], _currentLocation["longitude"],
            _settings.sensitivityRange).send(_socket);
      }
    } catch (exc) {
      print("Status broadcast exc: $exc");
    }
  }

  void _addLogMessage(String msg) {
    setState(() {
      msg = new DateTime.now().toString() + ": " + msg;
      if (_messages.length < _bufferSize) {
        _messages.add(new Text(msg));
      } else {
        _messages.removeLast();
        _messages.insert(0, new Text(msg));
      }
    });
    _messagesScrollController.jumpTo(0.0);
  }

  Text _getLogMessage(int index) {
    return _messages[index];
  }

  void _clearLogMessages() {
    _messages.clear();
    _startIndex = 0;
  }

  void _vibrationTimer() {
    if (_vibrationInterval == null) {
      //print("Vibration timer: idle");
      _stopVibrate();
      new Timer(VIBRATION_IDLE_TIMEOUT, _vibrationTimer);
    } else if (_vibrationInterval.inMilliseconds <= VIBRATION_LENGTH) {
      //print("Vibration timer: continuous");
      _vibrate(-1);
      new Timer(VIBRATION_IDLE_TIMEOUT, _vibrationTimer);
    } else {
      //print("Vibration timer: active: $_vibrationInterval");
      _vibrate(VIBRATION_LENGTH);
      new Timer(_vibrationInterval, _vibrationTimer);
    }
  }
}
