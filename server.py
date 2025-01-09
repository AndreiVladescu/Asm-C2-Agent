#!/usr/bin/python
from flask import Flask, Response, request

app = Flask(__name__)

@app.route('/', methods=['GET', 'POST'])
def handle_request():
    if request.method == 'GET':
        response_content = "pwd"
        return Response(response_content, status=200, mimetype='text/plain')

    elif request.method == 'POST':
        client_data = request.data.decode('utf-8')  # Decode the raw POST data
        print(f"Received POST data: {client_data}")

        return Response("Ok", status=200, mimetype='text/plain')


if __name__ == "__main__":
    app.run(host='127.0.0.1', port=8080)
