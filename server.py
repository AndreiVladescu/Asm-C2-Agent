#!/usr/bin/python
from flask import Flask, Response

app = Flask(__name__)

@app.route('/')
def handle_get():
    # HTTP GET request response
    response_content = "OK BOOMER"
    return Response(response_content, status=200, mimetype='text/plain')

if __name__ == "__main__":
    # Start the Flask server on localhost:8080
    app.run(host='127.0.0.1', port=8080)
