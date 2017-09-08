import 'dart:convert';
import 'dart:io';

class IncomingMessage {
  final String _value;
  const IncomingMessage._internal(this._value);

  static const PONG = const IncomingMessage._internal('pong');
  static const POWER_SPOT_RSSI = const IncomingMessage._internal('power-spot-rssi');
  static const CHANNELING_RSSI = const IncomingMessage._internal('channeling-rssi');

  String getTypeName() {
    return _value;
  }
}

abstract class Message {
  String id;
  String get type;
  Object get payload;

  Message(this.id);

  void send(Socket socket) {
    Map<String, Object> data = {
      "id": id,
      "type": type
    };
    if (payload != null) {
      data["payload"] = payload;
    }
    String msg = JSON.encode(data);
    print("Sending message: $msg");
    socket.write(msg);
  }
}

class PingMessage extends Message {
  PingMessage(String id) : super(id);

  @override
  String get type => "ping";

  @override
  Object get payload => null;
}

class StatusBroadcastMessage extends Message {
  double lat;
  double lon;
  int sensitivityRange;

  StatusBroadcastMessage(String id, this.lat, this.lon, this.sensitivityRange) : super(id);

  @override
  String get type => "status";

  @override
  Object get payload {
    return {"lat": lat, "lon": lon, "sensitivity-range": sensitivityRange};
  }
}
