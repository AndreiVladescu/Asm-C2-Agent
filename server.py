#!/usr/bin/python
from flask import Flask, Response

app = Flask(__name__)

@app.route('/')
def handle_get():
    response_content = "ls"
    return Response(response_content, status=200, mimetype='text/plain')

if __name__ == "__main__":
    app.run(host='127.0.0.1', port=8080)
