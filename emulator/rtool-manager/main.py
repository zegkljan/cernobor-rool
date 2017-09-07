import socket
import threading
import logging
import json
import queue
import sys
import collections
import enum
import math

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
        self.setDaemon(True)
        self.queue = queue.Queue()
        self.world = world
        self.coords = None
        self.sensitivity_range = float('inf')

    def run(self):
        self.sock.settimeout(1.0)
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

    def send_message(self, msg):
        msg_str = json.dumps(msg)
        self.log.debug('Sending message: {}'.format(msg_str))
        msg_bytes = msg_str.encode()
        self.sock.send(msg_bytes)

    def load_messages(self):
        buffer = ''
        state = None
        braces = 0
        while True:
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
    def __init__(self, config: dict):
        super().__init__(name='World')
        self.log = logging.getLogger(str(self.__class__))
        self.clients = []
        self.power_spots = config.get('power-spots', [])
        self.queue = queue.Queue()
        self.setDaemon(True)

    def join_all(self):
        while True:
            if self.clients:
                self.clients.pop().join()

    def run(self):
        while True:
            item = self.queue.get()
            self.log.debug('Received instruction: {}'.format(item))
            if item.type == ThreadMessageType.STATUS:
                self.handle_status(item.payload)

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


def main():
    logging.info('Starting...')
    config = dict()
    if len(sys.argv) > 1:
        config = json.load(open(sys.argv[1]))
    world = World(config)
    world.start()
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
        #world.join_all()
        raise

if __name__ == '__main__':
    logging.basicConfig(
        format='%(asctime)-15s [%(threadName)-21s]-%(levelname)-8s: %(message)s',
        level=logging.DEBUG
    )
    main()
