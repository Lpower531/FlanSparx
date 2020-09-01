include "Code/ObjNone.asm"
include "Code/ObjEnemyStill.asm"
include "Code/ObjGemRed.asm"
include "Code/ObjGemGreen.asm"
include "Code/ObjGemBlue.asm"
include "Code/ObjGemYellow.asm"
include "Code/ObjGemPurple.asm"
;Object data structure (16 bytes per object):
;   1 byte - ID
;   1 byte - Type
;   1 byte - Position Y
;   1 byte - Position X
;   1 byte - Rotation
;   1 byte - State:
;       0 - Normal
;       1 - Off screen
;       2 - Schedule despawn (distance)
;
;Object Table notes:
;   - ID $00 means not initialized (if $00 encountered in list, cut the loop short)
;   - ID $FF means removed (if $FF encountered in list, skip item)

SECTION "Objects", ROM0

;Input: A - object id, HL - VRAM position
SpawnObject:
    push hl
    push bc
    push de
;Store object ID -> B (value - 0x3F = id)
    sub $3F
    ld b, a

    call IsThisObjectDestroyed
    jr nz, .end

;Get position -> X, Y -> D, E
    ;X position - camera_x*2 + x_offset
    ld a, [camera_x]
    or a
    rla
    ld c, a
    ld a, [x_offset]
    add c
    ld d, a

    ;Y position - camera_y*2 + y_offset
    ld a, [camera_y]
    or a
    rla
    ld c, a
    ld a, [y_offset]
    add c
    ld e, a

;Claim a object slot -> C
    call ClaimSpriteSlot
    inc c ; cp $ff
    ; if c == $ff, it means the object already exists, so do not spawn
    jr z, .end
    dec c


;Get object data
    ;Get object data offset
    ld a, b
    dec a
    rla
    push bc
    ld c, a
    ld b, high(objects_level_test)

    ;Load bank
    di
    ld a, bank(objects_level_test)
    ld [set_bank], a
	ld [curr_bank], a

    ;BC is now a pointer to the right entry in the objects file 
    ;Read the object type
    inc bc
    ld a, [bc]
    pop bc
    push bc

    ld hl, object_table
    ld b, 0
    or a
    ; cd *= 8
    rl c
    rl b
    rl c
    rl b
    rl c
    rl b
    rl c
    rl b
    add hl, bc
    pop bc

;Write object data to object slot
    ld [hl], b ; write object id
    inc l
    ld [hl], a ; write object type
    inc l
    ld [hl], e ; write y position - why Y first? because the OAM stores object coordinates in that order for some reason
    inc l
    ld [hl], d ; write x position

.end
    pop de
    pop bc
    pop hl
    ei
    ret

;Input B - object id
;Output C - object slot
ClaimSpriteSlot:
    push hl
    ld hl, object_slots_occupied

    .CheckExistanceLoop
        ld a, [hl] ; read entry
        cp b ; if it's the same as the id, dont spawn the object
        jr z, .ObjectAlreadyExists
        inc l
        jr nz, .CheckExistanceLoop
        

    ld hl, object_slots_occupied
    ld c, 0

    .FindSlotLoop
        ld a, [hl] ; read entry
        or a ; cp 0 ; if free
        jr z, .freeSlotInRegC
        cp $ff ; if free
        jr z, .freeSlotInRegC
        inc l
        inc c
        jr nz, .FindSlotLoop
    
    .NoFreeSlot
    pop hl
    ret

    .ObjectAlreadyExists
    ld c, $FF
    pop hl
    ret

    .freeSlotInRegC
    ld [hl], b
    pop hl
    ret

;DE - pointer to object_slots_occupied index -> object_table
;HL - pointer to OAM
;B - index counter
UpdateObjectOAM:
    push hl
    push de
    ld hl, sprites_objects
    ld de, object_slots_occupied
    ld b, 0

.loop
    push bc
    ;Read a value from object_slots_occupied, and store it in B as well. Decrease because ID's start at 1 instead of 0
    ld a, [de]
    cp $FF
    jp z, .skipThisEntry ; if it's $FF, this slot is empty. skip part of the routine to save cpu time
    or a ; cp $00 
    jp z, .skipLoop ; if it's $00, it means the list ends here. stop the loop to save cpu
    dec a
    ld b, a

    ;Multiply by 4, and then 2 because an object takes 2 OAM slots
    or a
    rla
    rla
    rla
    
    pop bc
    push bc
    ;Get object_table offset by multiplying the index by 16 (16 bytes is the size of an entry)
    swap b
    ld a, b ; high byte
    and $0F
    ld c, a

    ld a, b ; low byte
    and $F0

    ;Load object_table into DE
    push de

    ;Low byte
    ld e, a

    ;High byte
    ld d, high(object_table)
    ld a, c
    add d
    ld d, a

    ;Get Type
    inc e
    ld a, [de]
    ld [curr_obj_type], a
    push hl
    ld hl, ObjectDisplayType
    add l
    ld l, a
    ld a, [hl]
    pop hl
    inc e
    or a ; cp 0
    jr z, .thisIsATile

.thisIsASprite
    inc e
    inc e
    inc e
    ld a, [de] ; -> on screen? -> A
    dec e
    dec e
    dec e

    or a ; cp 0
    jr nz, .onScreen


.notOnScreen
    pop de
    jr .skipThisEntry
.onScreen
    ;Run object code
    dec e ; move to object id
    ld a, [de] ; read it
    or a ; multiply by 2
    rla

    ;get address for object subroutine
    push hl
    ld h, high(ObjectSubroutines)
    ld l, a ; ObjectSubroutines is aligned, so no ADD required

    ;Load the subroutine pointer into HL
    ld c, [hl]
    inc l
    ld h, [hl]
    ld l, c

    ;Run the subroutine
    call RunSubroutine
    pop hl

    inc e

    ;LEFT SPRITE
    ; Y position
    ;load coordinates - abs_scroll_y
    ld a, [abs_scroll_y]

    ld b, a
    ld a, [de]
    
    ;position from 16x16 tile -> pixel
    or a
    rla
    rla
    rla

    sub b
    ld [hli], a

    ; X position
    ;load coordinates - abs_scroll_x, and check if not too far off screen
    inc e
    ld a, [abs_scroll_x]
    ld b, a
    ld a, [de]
    
    ;position from 16x16 tile -> pixel
    or a
    rla
    rla
    rla
    sub 12 ; sprite offset

    sub b
    ld [hli], a

    inc l
    inc l
    dec e

    ;RIGHT SPRITE
    ; Y position
    ;load coordinates - abs_scroll_y
    ld a, [abs_scroll_y]

    ld b, a
    ld a, [de]
    
    ;position from 16x16 tile -> pixel
    or a
    rla
    rla
    rla

    sub b
    ld [hli], a

    ; X position
    ;load coordinates - abs_scroll_x
    inc e
    ld a, [abs_scroll_x]
    ld b, a
    ld a, [de]
    
    ;position from 16x16 tile -> pixel
    or a
    rla
    rla
    rla
    sub 4

    sub b
    ld [hli], a
    jr .afterUpdate


.thisIsATile
    jr .afterUpdate

.afterUpdate
    pop de
    
    pop bc
    push bc
    call HandleObjectSprites
    inc l
    inc l

.skipThisEntry
    pop bc
    inc de

    inc b
    ld a, b
    cp $80
    jp nz, .loop

    jr .end
.skipLoop
    pop bc
    jr .end
.end
    ;Clear the rest of OAM
    xor a ; ld a, 0
    .clearRestLoop
        ld [hl], a
        inc l
        jr nz, .clearRestLoop
    pop de
    pop hl
    ret


;Input - HL points to right sprite tile ID
HandleObjectSprites:
    ld a, [curr_obj_type]
    cp $ff
    ret z
    or a
    rla
    
    ;HL -> DE
    push de
    ld d, h
    ld e, l

    ld h, high(SpriteDrawingSubroutines)
    ld l, a ; SpriteDrawingSubroutines is aligned, so no ADD required

    ;Load the subroutine pointer into HL
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    
    ;Run the subroutine
    call RunSubroutine
    pop de
    ret

CheckObjectsOnScreen:
    ;get current object index
    ld a, [curr_onscreen_check]
    ld e, a ; -> curr_onscreen_check into E, this is for updating curr_onscreen_check later
    ld b, 0
    ;multiply it by 16
    swap a
    ld d, a
    and $0F
    ld b, a
    ld a, d
    and $F0
    ld c, a
    ;store it into bc
    ld c, a
    ;and add it to hl
    ld hl, object_table
    add hl, bc

    ;check if valid object type
    ld a, [hl]
    or a ; cp 0 ; if A is 0, end of array reached, restart from start, and skip this loop for this frame
    jr z, .notValid
    cp $FF
    jr z, .end

    inc l
    inc l

    ;Y position
    ;top of screen
    ld b, [hl]
    inc l ; prepare the pointer for the next read
    ld a, [camera_y]
    or a ; reset c flag
    rla ; 16x16 -> 8x8
    sub 2 ; 2 tiles extra so it doesn't cut off early
    sub b ; will underflow if on screen
    jr nc, .notOnScreen ; if it doesnt underflow, it's not on screen

    ;bottom of screen
    ld a, [camera_y]
    or a ; reset c flag
    rla ; 16x16 -> 8x8
    add $14 ; screen height + 2
    sub b ; will underflow if not on screen
    jr c, .notOnScreen ; if it doesnt underflow, it's not on screen

    ;X position
    ;left of screen
    ld b, [hl]
    ld a, [camera_x]
    or a ; reset c flag
    rla ; 16x16 -> 8x8
    sub 2 ; 2 tiles extra so it doesn't cut off early
    sub b ; will underflow if on screen
    jr nc, .notOnScreen ; if it doesnt underflow, it's not on screen

    ;right of screen
    ld a, [camera_x]
    or a ; reset c flag
    rla ; 16x16 -> 8x8
    add $16 ; screen width + 2
    sub b ; will underflow if not on screen
    jr c, .notOnScreen ; if it doesnt underflow, it's not on screen
    
    jr .onScreen
.notValid
    xor a ; ld a, 0
    ld [curr_onscreen_check], a
    ret
.notOnScreen
    xor a ; ld a, 0
    jr .end
.onScreen
    ld a, 1
    ;jr .end
.end
    inc l
    inc l
    ld [hl], a
    inc e
    ld a, e
    ld [curr_onscreen_check], a
    or a ; cp 0
    jr nz, CheckObjectsOnScreen
    ret

;If there are a lot of FF values at the end of the table, shorten the table to make the table loops more efficient
CleanObjectTable:
;Look for first intance of $00
    push hl
    ld hl, object_table
    ld bc, 16 ; length of table entry 

    .findTableEndLoop
        ld a, [hl]
        or a ; cp 0 ; exit loop if the value at HL is $00
        jr z, .afterLoop
        ;otherwise, move to next entry
        add hl, bc
        jr .findTableEndLoop

    .afterLoop

    ld bc, -16 ;We're going backwards now
    .findTrueEndOfTable
        add hl, bc
        ld a, [hl]
        cp $FF
        jr nz, .afterLoop2
        ld [hl], 0
        jr .findTrueEndOfTable

    .afterLoop2

    pop hl
    ret

RunSubroutine:
    jp hl

SECTION "Object Subroutines", ROM0, ALIGN[8]
ObjectSubroutines:
    dw ObjNone_Update       ; 00 - none
    dw ObjEnemyStill_Update ; 01 - ObjEnemyStill
    dw ObjNone_Update       ; 02 - ObjGemRed
    dw ObjNone_Update       ; 03 - ObjGemGreen
    dw ObjNone_Update       ; 04 - ObjGemBlue
    dw ObjNone_Update       ; 05 - ObjGemYellow
    dw ObjNone_Update       ; 06 - ObjGemPurple

SECTION "Sprite Drawing Subroutines", ROM0, ALIGN[8]
SpriteDrawingSubroutines:
    dw ObjNone_Update       ; 00 - none
    dw DrawSprite_Enemy     ; 01 - ObjEnemyStill
    dw DrawSprite_GemRed    ; 02 - ObjGemRed
    dw DrawSprite_GemGreen  ; 03 - ObjGemGreen
    dw DrawSprite_GemBlue   ; 04 - ObjGemBlue
    dw DrawSprite_GemYellow ; 05 - ObjGemYellow
    dw DrawSprite_GemPurple ; 06 - ObjGemPurple

SECTION "Object Graphics Metadata", ROM0, ALIGN[8]
ObjectDisplayType:

;   00, 01, 02, 03, 04, 05, 06, 07, 08, 09, 0A, 0B, 0C, 0D, 0E, 0F
db  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1
db  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1
db  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1
db  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1
db  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1

