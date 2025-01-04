#!/usr/bin/python
import socket

def start_server():
    host = '127.0.0.1'  # Localhost
    port = 8080         # Port to bind

    # Create a socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        # Bind the socket to the address and port
        server_socket.bind((host, port))
        print(f"Server started on {host}:{port}")

        # Listen for incoming connections
        server_socket.listen(5)  # Allow up to 5 connections in the queue
        print("Waiting for a connection...")

        while True:
            # Accept a client connection
            client_socket, client_address = server_socket.accept()
            print(f"Connection established with {client_address}")

            # Send a welcome message to the client
            welcome_message = b"Hello, client! You are connected.\n"
            client_socket.send(welcome_message)

            # Close the client connection
            client_socket.close()
            print(f"Connection with {client_address} closed.")

    except KeyboardInterrupt:
        print("Shutting down the server.")
    finally:
        server_socket.close()

if __name__ == "__main__":
    start_server()
