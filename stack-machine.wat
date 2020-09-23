(module
    ;; imports
    (import "env" "log" (func $log (param i32)))
    (import "env" "mem" (memory $mem 1))
    (import "env" "programSize" (global $PROGRAM_SIZE i32))

    ;; types
    (type $tmain (func))

    ;; exports
    (export "mem" (memory $mem))
    (export "WM_ADDR" (global $WM_ADDR))
    (export "stack_top_pointer" (global $stack_top_pointer))
    (export "main" (func $main))

    ;; closure encoding tags
    (global $CLS_I   i32 (i32.const 0))
    (global $CLS_K   i32 (i32.const 1))
    (global $CLS_S   i32 (i32.const 2))
    (global $CLS_AK  i32 (i32.const 3))
    (global $CLS_AS1 i32 (i32.const 4))
    (global $CLS_AS2 i32 (i32.const 5))

    (global $CLS_SIZE i32 (i32.const 13)) ;; encoded closure size (32 bit + 8 bit + 64 bit)

    ;; built-in closure ids
    (global $CLS_ID_I i32 (i32.const 0))
    (global $CLS_ID_K i32 (i32.const 1))
    (global $CLS_ID_S i32 (i32.const 2))

    (global $STACK_SIZE i32 (i32.const 1024)) ;; command stack size in bytes
    (global $STACK_FRAME_SIZE i32 (i32.const 4)) ;; command stack frame size in bytes

    (global $WM_ADDR (mut i32) (i32.const 0)) ;; working memory address, initialized based on the $PROGRAM_SIZE
    (global $CLS_HEAP_ADDR (mut i32) (i32.const 0)) ;; current closure heap address (initialized with $WM_ADDR + $STACK_SIZE)

    (global $stack_top_pointer (mut i32) (i32.const 0)) ;; current stack top pointer (initialized with $wm_offset)
    (global $cls_heap_offset (mut i32) (i32.const 0)) ;; current closure heap offset (initialized with $wm_offset + $STACK_SIZE)
    (global $cls_id (mut i32) (i32.const 0)) ;; next closure id

    (func $write_cls (param $tag i32) (param $data i32)
        ;; TODO: speed-up with shifts
        (local $offset i32)
        (local.set $offset (global.get $cls_heap_offset))
        (i32.store (local.get $offset) (global.get $cls_id)) ;; cls_id
        (global.set $cls_id (i32.add (global.get $cls_id) (i32.const 1))) ;; inc cls_id
        (i32.store8 (i32.add (local.get $offset) (i32.const 4)) (local.get $tag)) ;; tag
        (i32.store (i32.add (local.get $offset) (i32.const 5)) (local.get $data)) ;; data
        (global.set $cls_heap_offset (i32.add (local.get $offset) (global.get $CLS_SIZE)))
    )

    (func $write_cls_ext (param $tag i32) (param $data1 i32) (param $data2 i32)
        (local $offset i32)
        (local.set $offset (global.get $cls_heap_offset))
        (call $write_cls (local.get $tag) (local.get $data1))
        (i32.store (i32.add (local.get $offset) (i32.const 9)) (local.get $data2)) ;; data2
    )

    (func $stack_pop (result i32)
        ;; move the stack top pointer
        (global.set $stack_top_pointer
            (i32.sub
                (global.get $stack_top_pointer)
                (global.get $STACK_FRAME_SIZE)
            )
        )
        (i32.load (global.get $stack_top_pointer))
    )

    (func $stack_push (param $value i32)
        (i32.store (global.get $stack_top_pointer) (local.get $value))
        ;; move the stack top pointer
        (global.set $stack_top_pointer
            (i32.add
                (global.get $stack_top_pointer)
                (global.get $STACK_FRAME_SIZE)
            )
        )
    )

    (func $stack_peek (result i32)
        (i32.load
            (i32.sub
                (global.get $stack_top_pointer)
                (global.get $STACK_FRAME_SIZE)
            )
        )
    )

    (func $apply (param $func_id i32)
        (local $arg_id i32)
        (local $cls_tag i32)
        (local $cls_data i32)
        (local $cls_data2 i32)

        (if (i32.eq (local.get $func_id) (global.get $CLS_ID_I)) ;; func = I
            (then) ;; do nothing
            (else
                (if (i32.eq (local.get $func_id) (global.get $CLS_ID_K)) ;; func = K
                    (then
                        ;; pop the arg
                        (local.set $arg_id (call $stack_pop))
                        ;; write an AK-closure on the heap
                        (call $write_cls (global.get $CLS_AK) (local.get $arg_id))
                        ;; push cls_id
                        (call $stack_push (i32.sub (global.get $cls_id) (i32.const 1)))
                    )
                    (else
                        (if (i32.eq (local.get $func_id) (global.get $CLS_ID_S)) ;; func = S
                            (then
                                ;; pop the arg
                                (local.set $arg_id (call $stack_pop))
                                ;; write an AS1-closure on the heap
                                (call $write_cls (global.get $CLS_AS1) (local.get $arg_id))
                                ;; push cls_id
                                (call $stack_push (i32.sub (global.get $cls_id) (i32.const 1)))
                            )
                            ;; push cmd_id
                            (else ;; $func_id refers to a closure on the heap
                                ;; load closure tag
                                (local.set $cls_tag
                                    (i32.load8_u
                                        (i32.add
                                            (i32.add
                                                (i32.mul (local.get $func_id) (global.get $CLS_SIZE))
                                                (global.get $CLS_HEAP_ADDR)
                                            )
                                            (i32.const 4) ;; cls tag offset
                                        )
                                    )
                                )

                                ;; load closure data (closure id)
                                (local.set $cls_data
                                    (i32.load
                                        (i32.add
                                            (i32.add
                                                (i32.mul (local.get $func_id) (global.get $CLS_SIZE))
                                                (global.get $CLS_HEAP_ADDR)
                                            )
                                            (i32.const 5) ;; cls data1 offset
                                        )
                                    )
                                )

                                ;; if closure is AK
                                (if (i32.eq (local.get $cls_tag) (global.get $CLS_AK))
                                    (then
                                        ;; pop the arg
                                        (local.set $arg_id (call $stack_pop))
                                        ;; push the arg cmd id
                                        (call $stack_push (local.get $cls_data))
                                    )
                                    (else
                                        ;; closure is AS1
                                        (if (i32.eq (local.get $cls_tag) (global.get $CLS_AS1))
                                            (then
                                                ;; pop the arg2
                                                (local.set $arg_id (call $stack_pop))
                                                ;; create (AS2 arg1 arg2)
                                                (call $write_cls_ext (global.get $CLS_AS2) (local.get $cls_data) (local.get $arg_id))
                                                ;; push the new cls_id
                                                (call $stack_push (i32.sub (global.get $cls_id) (i32.const 1)))
                                            )
                                            (else ;; closure is AS2
                                                ;; peek without popping becase $apply below expects the arg on the stack
                                                (local.set $arg_id (call $stack_peek))

                                                ;; load 2nd closure data (closure id)
                                                (local.set $cls_data2
                                                    (i32.load
                                                        (i32.add
                                                            (i32.add
                                                                (i32.mul (local.get $func_id) (global.get $CLS_SIZE))
                                                                (global.get $CLS_HEAP_ADDR)
                                                            )
                                                            (i32.const 9) ;; cls data2 offset
                                                        )
                                                    )
                                                )

                                                ;; apply the g-func to the arg
                                                (call $apply (local.get $cls_data2))

                                                ;; restore the original arg
                                                (call $stack_push (local.get $arg_id))

                                                ;; apply the f-func to the arg
                                                (call $apply (local.get $cls_data))

                                                ;; apply the func on the stack to the arg
                                                (call $apply (call $stack_pop))
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )

    (func $main (type $tmain)
        (local $cmd_addr i32)
        (local $cmd i32)

        (local.set $cmd_addr (i32.const 0))

        ;; init memory layout
        (;
            |-- Program Memory --| $PROGRAM_SIZE bytes
            |--  Stack Memory  --| $STACK_SIZE bytes
            |--   Heap Memory  --| No fixed size
        ;)

        (global.set $WM_ADDR (global.get $PROGRAM_SIZE))
        (global.set $CLS_HEAP_ADDR (i32.add (global.get $WM_ADDR) (global.get $STACK_SIZE)))

        ;; init memory pointers
        (global.set $stack_top_pointer (global.get $WM_ADDR))
        (global.set $cls_heap_offset (i32.add (global.get $WM_ADDR) (global.get $STACK_SIZE)))

        ;; init closure heap
        (call $write_cls (global.get $CLS_I) (i32.const 0))
        (call $write_cls (global.get $CLS_K) (i32.const 0))
        (call $write_cls (global.get $CLS_S) (i32.const 0))

        (loop $EVAL_LOOP
            (local.set $cmd (i32.load8_u (local.get $cmd_addr)))
            (if (i32.eq (local.get $cmd) (i32.const 0)) ;; cmd = I
                ;; push the I cmd_id
                (then (call $stack_push (global.get $CLS_ID_I)))
                (else
                    (if (i32.eq (local.get $cmd) (i32.const 1)) ;; cmd = K
                        ;; push the K cmd_id
                        (then (call $stack_push (global.get $CLS_ID_K)))
                        (else
                            (if (i32.eq (local.get $cmd) (i32.const 2)) ;; cmd = S
                                (then (call $stack_push (global.get $CLS_ID_S)))
                                (else ;; cmd = A
                                    ;; pop and apply the func
                                    (call $apply (call $stack_pop))
                                )
                            )
                        )
                    )
                )
            )

            (local.set ;; next $cmd_addr
                $cmd_addr
                (i32.add
                    (local.get $cmd_addr)
                    (i32.const 1)
                    )
                )

            (if (i32.lt_u (local.get $cmd_addr) (global.get $WM_ADDR))
                (br $EVAL_LOOP)
            )

        )
    )

    (start $main)
)
