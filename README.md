# Assembly C2 Agent PoC

## Introduction

This is a proof of concept C2 agent is written for Linux ABI, to demonstrates how a simplistic agent works and how to write it in low level ASM.

## Usage

### Requirments 
` sudo apt update && sudo apt install make nasm -y && \
pip install flask && \
git clone https://github.com/AndreiVladescu/Asm-C2-Agent && \
cd Asm-C2-Agent`

First of all, launch the `server.py` component using `python3 server.py`, that will be listening on all IP addresses and port 8080. This script will run on the C2 server.

To update the IP of the C2, go into the `agent.s` file and update the server to your IP.

### Running

To run the C2, update the command into the `server.py`, then compile the agent using `make` and run it on the target Linux PC. To see the results, look into the output of the `server.py`.
