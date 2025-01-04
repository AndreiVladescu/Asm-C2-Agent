all: agent

agent: agent.o
		ld agent.o -o agent

agent.o: agent.s
		nasm -f elf64 agent.s -o agent.o

clean:
		rm -f agent
		rm -f agent.o