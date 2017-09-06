import socket
import threading
import logging
import json
import queue
import sys
import collections
import enum
import geopy
import geopy.distance


BUFFER_SIZE = 1024

ThreadMessage = collections.namedtuple('ThreadMessage', ['type', 'payload'])


class ThreadMessageType(enum.Enum):
    STATUS = 1
    DISTANCE_REPORT = 2


class Client(threading.Thread):
    def __init__(self, sock: socket.socket, address, port, world: World):
        super().__init__(name='{}:{}'.format(address, port))
        self.log = logging.getLogger('')
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
                self.log.info('Received message: {}'.format(msg))
                self.handle_message(msg)
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

    def send_message(self, msg):
        self.sock.send(json.dumps(msg).encode())

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
        self.clients = []
        self.power_spots = config.get('power-spots', [])
        self.queue = queue.Queue()

    def join_all(self):
        while True:
            if self.clients:
                self.clients.pop().join()

    def run(self):
        while True:
            item = self.queue.get()
            if item.type == ThreadMessageType.STATUS:
                self.handle_status(item.payload)

    def handle_status(self, client: Client):
        distances = zip(self.power_spots,
                        [self.get_distance(client.coords, spot)
                         for spot in self.power_spots])
        spot, distance = min(distances, key=lambda _, d: d)
        client.queue.put(ThreadMessage(ThreadMessageType.DISTANCE_REPORT,
                                       distance))

    @staticmethod
    def get_distance(a, b):
        return geopy.distance.vincenty((a['lat'], a['lon']),
                                       (b['lat'], b['lon'])).meters


def main():
    logging.info('Starting...')
    if len(sys.argv) > 1:
        config = json.load(open(sys.argv[1]))
    world = World(config)
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind(('', 6644))
    server_socket.listen(5)
    logging.info('Listening at {}'.format(server_socket.getsockname()))
    try:
        while True:
            (client_socket, address) = server_socket.accept()
            logging.info('Accepted new connection: {}'.format(address))
            client_thread = Client(client_socket, *address)
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
