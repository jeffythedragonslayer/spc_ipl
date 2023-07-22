; I didn't like how terse the existing SPC700 boot rom disassemblies were, so here is one that is extremely verbose
; and explains things in excruciating detail

.org $FFC0                  ; the SPC boot rom (aka "initial program loader" or IPL) is located at $FFC0 in ARAM
init_stack_pointer:
        mov X, #$EF
        mov SP, X           ; initialize stack pointer to $EF

        mov A, #$00         ; we will be using a zero in the accumulator in order
                            ; to zerofill the zeropage
zerofill_loop:
        mov (X), A          ; zero out the zeropage location specified by X
        dec X               ; move cursor towards the beginning of the zeropage
        bne zerofill_loop   ; keep zerofilling until we reach the very first address

send_sheep:
        mov CPUIO0, #$AA    ; send the 5A22 the "sheep" code BBAAh to indicate that the
        mov CPUIO1, #$BB    ; SPC is ready to receive the target ARAM address, where it will
                            ; put the driver code its going to download

        ; when the 5A22 has recieved the sheep code, it will reply with:
        ;     * the constant #$CC (the "mario kart" code) on port 0
        ;     * something nonzero on port 1 to indicate it wants to upload the target ARAM address of the first/next block of driver code and then upload the block
        ;                 (a zero would indicate that the SPC should now run the driver)
        ;     * the target ARAM address of the driver on ports 2 & 3 (low byte in port 2, high byte in port 3)

confirm_mario_kart:
        cmp CPUIO0, #$CC        ; wait for 5A22 to reply with #$CC
        bne confirm_mario_kart  ; if SPC has not recieved reply yet, keep waiting

        bra main_loop       ; I don't know why Nintendo didn't just put the main
                            ; loop here, but whatever - jump over the transfer routine to it

transfer_a_block:            ; the 5A22 will write a zero to Port 0 when it is ready to upload a block
        mov Y, CPUIO0        
        bne transfer_a_block ; wait until that zero appears

wait_for_next_byte_signal_or_end_of_block_signal:
        cmp Y, CPUIO0                   ; usually, the index into the block that the 5A22 remembers should match our saved, expected index (in Y) -
                                        ; if they do match, then that is the "next byte" signal

        bne indices_do_not_match        ; but if they don't, that is the "end of block" signal, so don't download a byte

        ; the SPC got the "next byte" signal
        ; the value of Y is the expected index of the next byte in the block, which we are about to download

        mov A, CPUIO1       ; SPC downloads a byte of driver code from the 5A22
        mov CPUIO0, Y       ; SPC echos the index back to the 5A22 to acknowledge
        mov [$00]+Y, A      ; SPC stores the downloaded byte in ARAM location that was specified in the main loop (pointed to by $00) plus the index (Y)
        inc Y               ; increment index, get ready to download next byte
        bne wait_for_next_byte_signal_or_end_of_block_signal
        
        ; Y has now overflowed to zero, which is going to be a problem.
        ; Remember that a "page" in 65x is 256 bytes, and since Y is our cursor it is now pointing to the beginning of the page again, which contains
        ; driver code we already downloaded.  To prevent overwritting it, we increment the more significant byte of the target ARAM address,
        ; which will move us to the next page
        inc $01

        ; the very next BPL will now send us back to waiting for the next byte/end block signal

indices_do_not_match:
        ; the 5A22's index does not match our saved, expected index (in Y)
        ; but, maybe the 5A22 is just being slow and hasn't written its new index to the port yet

        ; I don't know why Nintendo has these three instructions here,
        ; but the exact same CMP statement is about to happen
        ; maybe they were just trying to fill up space to take up 64 bytes?

        bpl wait_for_next_byte_signal_or_end_of_block_signal    ; if Y > CPUIO, then the 5A22 hasn't incremented its index yet, so go back to waiting
        cmp Y, CPUIO0                                           ; does the 5A22's index match our saved expected index (in Y)?
                                                                ; the subtraction this command does internally is Y - CPUIO0
                                                                ; so the negative flag is set iff CPUIIO > Y
        bpl wait_for_next_byte_signal_or_end_of_block_signal

        ; the indexes do not match, and CPUIO < Y.  So we know that the 5A22 intentionally sent us the 
        ; "end of block" signal and is not just being slow, so drop back to main loop

main_loop:
        movw YA, CPUIO2         ; SPC gets target ARAM address from 5A22 over ports 2 & 3
        movw $00, YA            ; store target ARAM address at very first word in ARAM
        movw YA, CPUIO0         ; SPC gets the command from the 5A22 (non-zero means "begin transfer," zero means "start running driver")
                                ; into Y and mario kart code into A

        mov CPUIO0, A           ; the SPC acknowledges by echoing the mario kart code CC back to the 5A22

        mov A, Y                ; move the command code in Y over to X
        mov X, A                ; "mov X, Y" doesn't exist, so use A as an intermediary

        bne transfer_a_block    ; a non-zero command means "begin transfer," so jump to the transfer routine
        jmp [$0000+X]           ; a zero command means "start running the freshly uploaded driver," so jump to it
.dw $FFC0                       ; reset vector