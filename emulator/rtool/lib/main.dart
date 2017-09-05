import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location/location.dart';
import 'messages.dart';

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

  final TextEditingController _serverIpTextController = new TextEditingController();
  final TextEditingController _idTextController = new TextEditingController();
  final ScrollController _messagesScrollController = new ScrollController();

  final int _bufferSize = 500;
  List<Text> _messages = <Text>[];
  int _startIndex = 0;

  static const MethodChannel platform = const MethodChannel("cernobor");
  bool vibrating = false;
  bool sounding = false;

  bool _running = false;
  Socket _socket;
  Location _location = new Location();
  Timer _statusTimer;

  @override
  Widget build(BuildContext context) {
    Scaffold scaffold = new Scaffold(
      appBar: new AppBar(title: new Text("RTool")),
      drawer: new Drawer(
        child: new ListView(
          children: <Widget>[
            new DrawerHeader(child: new Text("Settings")),
            new ListTile(
              title: new Text('start/stop vibration'),
              onTap: () {
                if (vibrating) {
                  _stopVibrate();
                } else {
                  _vibrate(8);
                }
                vibrating = !vibrating;
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
            )
          ],
        ),
      ),
      body: new Column(
        children: <Widget>[
          new TextFormField(
            controller: _serverIpTextController,
            decoration: new InputDecoration.collapsed(
                hintText: "server IP address"
            ),
          ),
          new TextFormField(
            controller: _idTextController,
            decoration: new InputDecoration.collapsed(
                hintText: "tool ID"
            ),
            keyboardType: TextInputType.number,
          ),
          new Row(
            children: <Widget>[
              new RaisedButton(
                onPressed: () => _handleStartStop(),
                color: Theme.of(context).buttonColor,
                child: new Text(_running ? "Stop" : "Start"),
              ),
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
              padding: new EdgeInsets.only(bottom: 20.0),
              reverse: false,
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

  void _handleStartStop() {
    _running = !_running;
    setState(() {
      _addLogMessage(_running ? "Started." : "Stopped.");
    });
    if (_running) {
      Socket.connect(_serverIpTextController.text, 6644).then((socket) {
        setState(() => _addLogMessage("Connected!"));
        _socket = socket;
        _socket.listen((data) {
          setState(() => _addLogMessage(UTF8.decode(data)));
        });
        _statusTimer = new Timer.periodic(STATUS_BROADCAST_TIMEOUT, (_) {
          print("broadcasting status");
          _statusBroadcast();
        });
      });
    } else {
      if (_socket != null) {
        _socket.close();
      }
      _socket = null;
      if (_statusTimer != null) {
        _statusTimer.cancel();
      }
    }
  }

  String _getId() {
    return _idTextController.text;
  }

  Future<Null> _playFrequency(int frequency, [int duration]) async {
    var params = {"frequency": frequency};
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

  Future<Null> _vibrate(int level, [int duration]) async {
    var params = {"level": level};
    if (duration != null) {
      print("Trying to vibrate for $duration ms");
      params["duration"] = duration;
    } else {
      print("Trying to vibrate for indefinitely");
    }
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
    new PingMessage(_getId()).send(_socket);
  }

  void _statusBroadcast() {
    try {
      _location.getLocation.then((Map<String, double> loc) {
        new StatusBroadcastMessage(_getId(), loc["latitude"], loc["longitude"]).send(_socket);
      });
    } catch (exc) {
      print("Status broadcast exc: $exc");
    }
  }

  void _addLogMessage(String msg) {
    msg = new DateTime.now().toString() + ": " + msg;
    if (_messages.length < _bufferSize) {
      _messages.add(new Text(msg));
    } else {
      _messages[_startIndex] = new Text(msg);
      _startIndex = (_startIndex + 1) % _bufferSize;
    }
    _messagesScrollController.jumpTo(_messagesScrollController.position.maxScrollExtent);
  }

  Text _getLogMessage(int index) {
    return _messages[(index + _startIndex) % _bufferSize];
  }

  void _clearLogMessages() {
    _messages.clear();
    _startIndex = 0;
  }
}
