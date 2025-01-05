#!/usr/bin/python
import socket

def start_http_server():
    host = '127.0.0.1'  # Localhost
    port = 8080         # Port to bind

    # Create a socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        # Bind the socket to the address and port
        server_socket.bind((host, port))
        print(f"HTTP Server started on {host}:{port}")

        # Listen for incoming connections
        server_socket.listen(5)  # Allow up to 5 connections in the queue
        print("Waiting for a connection...")

        while True:
            # Accept a client connection
            client_socket, client_address = server_socket.accept()
            print(f"Connection established with {client_address}")

            # Send an HTTP GET command to the agent
            get_request = b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            client_socket.sendall(get_request)
            print("Sent HTTP GET request to the agent.")

            # Close the client connection
            client_socket.close()
            print(f"Connection with {client_address} closed.")

    except KeyboardInterrupt:
        print("Shutting down the server.")
    finally:
        server_socket.close()

if __name__ == "__main__":
    start_http_server()
