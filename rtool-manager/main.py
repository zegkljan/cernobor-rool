import socket
import threading
import logging
import json


BUFFER_SIZE = 1024


class Client(threading.Thread):
    def __init__(self, sock: socket.socket, address, port):
        super().__init__(name='{}:{}'.format(address, port))
        self.log = logging.getLogger('')
        self.sock = sock
        self.setDaemon(True)

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


class World:
    def __init__(self):
        self.clients = []

    def join_all(self):
        while True:
            if self.clients:
                self.clients.pop().join()


def main():
    logging.info('Starting...')
    world = World()
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
