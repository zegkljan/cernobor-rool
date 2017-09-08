import collections
import copy
import enum
import json
import logging
import math
import os.path
import queue
import socket
import sys
import threading

import flask
import geopy
import geopy.distance

BUFFER_SIZE = 1024
FREQUENCY = 868e6
FSPL_CONSTANT = (20 * math.log10(FREQUENCY) +
                 20 * math.log10(4 * math.pi / 299792458))

ThreadMessage = collections.namedtuple('ThreadMessage', ['type', 'payload'])


class ThreadMessageType(enum.Enum):
    STATUS = 1
    POWER_SPOT_RSSI = 2
    ADD_POWER_SPOT = 3
    GET_POWER_SPOTS = 4
    DELETE_POWER_SPOT = 5
    TERMINATE = 6


def get_distance(a, b):
    return geopy.distance.great_circle((a['lat'], a['lon']),
                                       (b['lat'], b['lon'])).meters


def fspl(d: float) -> float:
    return 20 * math.log10(d) + FSPL_CONSTANT


class Client(threading.Thread):
    def __init__(self, sock: socket.socket, address, port, world):
        super().__init__(name='{}:{}'.format(address, port))
        self.log = logging.getLogger(str(self.__class__))
        self.sock = sock
        self.setDaemon(False)
        self.queue = queue.Queue()
        self.world = world
        self.coords = None
        self.sensitivity_range = float('inf')
        self.keep_running = True

    def run(self):
        self.sock.settimeout(0.2)
        for msg in self.load_messages():
            if msg is not None:
                self.log.debug('Received message: {}'.format(msg))
                self.handle_message(msg)
            try:
                item = self.queue.get_nowait()
                self.log.debug('Received instruction: {}'.format(item))
                self.handle_instruction(item)
            except queue.Empty as e:
                pass
        self.log.info('Closing connection.')
        self.sock.close()

    def handle_message(self, msg):
        if msg['type'] == 'ping':
            self.send_message({'type': 'pong'})
        elif msg['type'] == 'status':
            self.coords = {'lat': msg['payload']['lat'],
                           'lon': msg['payload']['lon']}
            self.sensitivity_range = msg['payload']['sensitivity-range']
            self.world.queue.put(ThreadMessage(ThreadMessageType.STATUS, self))

    def handle_instruction(self, item: ThreadMessage):
        if item.type == ThreadMessageType.POWER_SPOT_RSSI:
            self.send_message({'type': 'power-spot-rssi',
                               'dBm': item.payload['dBm'],
                               'dBm-threshold': item.payload['dBm-threshold'],
                               'distance': item.payload['distance'],
                               'name': item.payload['name']})
        elif item.type == ThreadMessageType.TERMINATE:
            self.keep_running = False

    def send_message(self, msg):
        msg_str = json.dumps(msg)
        self.log.debug('Sending message: {}'.format(msg_str))
        msg_bytes = msg_str.encode()
        self.sock.send(msg_bytes)

    def load_messages(self):
        buffer = ''
        state = None
        braces = 0
        while self.keep_running:
            try:
                data = self.sock.recv(BUFFER_SIZE)
            except socket.timeout:
                yield None
                continue
            if data == b'':
                self.log.debug('End of stream.')
                return
            for d in str(data, encoding='utf-8'):
                if state is None:
                    if d != '{':
                        continue
                    buffer += d
                    state = '{'
                    braces += 1
                elif state == '{':
                    if d == '"':
                        buffer += d
                        state = '"'
                    elif d == '{':
                        buffer += d
                        braces += 1
                    elif d == '}':
                        buffer += d
                        braces -= 1
                        if braces == 0:
                            self.log.debug('About to parse: {}'.format(buffer))
                            yield json.loads(buffer)
                            state = None
                            buffer = ''
                    else:
                        buffer += d
                elif state == '"':
                    if d == '\\':
                        state = '\\'
                    elif d == '"':
                        buffer += d
                        state = '{'
                    else:
                        buffer += d
                elif state == '\\':
                    if d == '\\':
                        buffer += '\\'
                    elif d == '"':
                        buffer += '"'
                    else:
                        buffer += '\\' + d


class World(threading.Thread):
    def __init__(self, config: dict, config_file: str):
        super().__init__(name='World')
        self.log = logging.getLogger(str(self.__class__))
        self.clients = []
        self.power_spots = config.get('power-spots', [])
        self.queue = queue.Queue()
        self.config_file = config_file
        self.setDaemon(False)
        self.keep_running = True

    def join_all(self):
        while True:
            if self.clients:
                self.clients.pop().join()
            return

    def run(self):
        while self.keep_running:
            item = self.queue.get()
            self.log.debug('Received instruction: {}'.format(item))
            if item.type == ThreadMessageType.STATUS:
                self.handle_status(item.payload)
            elif item.type == ThreadMessageType.ADD_POWER_SPOT:
                self.handle_add_power_spot(item.payload)
            elif item.type == ThreadMessageType.GET_POWER_SPOTS:
                self.handle_get_power_spots(item.payload)
            elif item.type == ThreadMessageType.DELETE_POWER_SPOT:
                self.handle_delete_power_spot(item.payload)
            elif item.type == ThreadMessageType.TERMINATE:
                self.handle_terminate()
        self.log.info('Terminated.')

    def handle_status(self, client: Client):
        distances = zip(self.power_spots,
                        [get_distance(client.coords, spot)
                         for spot in self.power_spots])
        spot, d = min(distances, key=lambda x: x[1])
        payload = {'dBm': spot['radiation-strength'] - fspl(d),
                   'dBm-threshold': -fspl(client.sensitivity_range),
                   'distance': d,
                   'name': spot['name']}
        client.queue.put(ThreadMessage(ThreadMessageType.POWER_SPOT_RSSI,
                                       payload))

    def handle_add_power_spot(self, power_spot):
        power_spot['lat'] = float(power_spot['lat'])
        power_spot['lon'] = float(power_spot['lon'])
        power_spot['radiation-strength'] = float(power_spot['radiation-strength'])
        self.log.debug('Adding power spot: {}'.format(power_spot))
        self.power_spots.append(power_spot)
        if self.config_file is None:
            return
        with open(self.config_file, mode='w') as f:
            json.dump({'power-spots': self.power_spots}, f, indent=2,
                      sort_keys=True)

    def handle_get_power_spots(self, q: queue.Queue):
        q.put(copy.deepcopy(self.power_spots))

    def handle_delete_power_spot(self, name):
        self.log.debug('Deleting power spot: {}'.format(name))
        self.power_spots = [s for s in self.power_spots if s['name'] != name]
        with open(self.config_file, mode='w') as f:
            json.dump({'power-spots': self.power_spots}, f, indent=2,
                      sort_keys=True)

    def handle_terminate(self):
        self.log.info('Terminating...')
        for client in self.clients:
            self.log.debug('Senting termination instruction to '
                           'client {}'.format(client.name))
            client.queue.put(ThreadMessage(ThreadMessageType.TERMINATE, None))
        self.log.info('Waiting for all clients to terminate...')
        self.join_all()
        self.keep_running = False


def simple_response(code, message):
    return ('<html><body><h1>{}</h1></body></html>'.format(message),
            code, {'ContentType': 'text/html'})


def main():
    logging.info('Starting...')
    config = dict()
    config_file = None
    if len(sys.argv) > 1:
        config_file = sys.argv[1]
        config = json.load(open(config_file))
    world = World(config, config_file)
    world.start()

    flask_app = flask.Flask(__name__, static_folder='')
    flask_log = logging.getLogger('web')

    @flask_app.route('/')
    def serve_page():
        return flask_app.send_static_file('map.html')

    @flask_app.route('/save', methods=['GET'])
    def save_power_spot():
        args = flask.request.args
        lat = args.get('lat')
        lon = args.get('lon')
        name = args.get('name')
        flask_log.debug('Saving power spot: lat={}, lon={}, name={}'
                        .format(lat, lon, name))
        world.queue.put(ThreadMessage(
            ThreadMessageType.ADD_POWER_SPOT,
            {'lat': lat, 'lon': lon, 'name': name, 'radiation-strength': 0}))
        return '', 200

    @flask_app.route('/delete', methods=['GET'])
    def delete_power_spot():
        args = flask.request.args
        name = args.get('name')
        flask_log.debug('Deleting power spot: name={}'
                        .format(name))
        world.queue.put(ThreadMessage(
            ThreadMessageType.DELETE_POWER_SPOT, name))
        return '', 200

    @flask_app.route('/power-spots')
    def power_spots():
        q = queue.Queue()
        world.queue.put(ThreadMessage(ThreadMessageType.GET_POWER_SPOTS, q))
        spots = q.get()
        return json.dumps(spots), '200', {'ContentType': 'application/json'}

    @flask_app.route('/apk')
    def apk():
        if not os.path.exists('rtool.apk'):
            return simple_response(404, 'apk is not available')
        return flask.send_file(
            'rtool.apk', mimetype='application/vnd.android.package-archive',
            attachment_filename='rtool.apk', as_attachment=True)

    flask_thread = threading.Thread(
        target=lambda: flask_app.run(debug=False, host='0.0.0.0',
                                     port='8080'),
        name='web',
        daemon=True
    )
    flask_thread.start()

    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind(('', 6644))
    server_socket.listen(5)
    logging.info('Listening at {}'.format(server_socket.getsockname()))
    try:
        while True:
            (client_socket, address) = server_socket.accept()
            logging.info('Accepted new connection: {}'.format(address))
            client_thread = Client(client_socket, *address, world)
            world.clients.append(client_thread)
            client_thread.start()
    except:
        logging.warning('Received exception.', exc_info=True)
        world.queue.put(ThreadMessage(ThreadMessageType.TERMINATE, None))

if __name__ == '__main__':
    logging.basicConfig(
        format='%(asctime)-15s [%(threadName)-21s]-%(levelname)-8s: %(message)s',
        level=logging.DEBUG
    )
    main()
