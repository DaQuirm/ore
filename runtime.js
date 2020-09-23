const fs = require('fs').promises;

Promise.all([
    fs.readFile('./stack-machine.wasm'),
    fs.readFile('./program.wasm')
]).then(([stackMachine, program]) =>
    WebAssembly.instantiate(program)
        .then(programWA => WebAssembly.instantiate(
            stackMachine,
            { env:
                { log: console.log
                , mem: programWA.instance.exports.mem
                , programSize: programWA.instance.exports.PROGRAM_SIZE
                }
            }
        ))
        .then(result => {
            const STACK_SIZE = result.instance.exports.STACK_SIZE.value;
            const STACK_FRAME_SIZE = result.instance.exports.STACK_FRAME_SIZE.value;

            const CLS_SIZE = result.instance.exports.CLS_SIZE.value;
            const CLS_HEAP_ADDR = result.instance.exports.CLS_HEAP_ADDR.value;

            const workingMemoryOffset = result.instance.exports.WM_ADDR.value;
            console.log(`Working Memory address: ${workingMemoryOffset}`);
            const programMem = new Uint8Array(result.instance.exports.mem.buffer, 0, workingMemoryOffset);

            const stackTopPointer = result.instance.exports.stack_top_pointer.value;
            console.log(`Stack Top pointer: ${stackTopPointer}`);
            const stackMem = new Uint8Array(result.instance.exports.mem.buffer, workingMemoryOffset, stackTopPointer - workingMemoryOffset);

            const clsHeapPointer = result.instance.exports.cls_heap_pointer.value;
            const closureMemoryTotal = clsHeapPointer - CLS_HEAP_ADDR;
            console.log(`Heap pointer: ${clsHeapPointer}, ${closureMemoryTotal / CLS_SIZE} closures ⨉ ${CLS_SIZE} bytes`);

            const heapMem = new Uint8Array(result.instance.exports.mem.buffer, workingMemoryOffset + STACK_SIZE, closureMemoryTotal);
            console.log(`Program Memory: ${programMem}\n`);

            const stackClss = [];

            for (let i = 0; i < stackMem.length; i += STACK_FRAME_SIZE) {
                const buffer = Buffer.from(stackMem.subarray(i, i + STACK_FRAME_SIZE));
                const clsId = buffer.readUIntLE(0, buffer.length);
                stackClss.push(clsId);
            }

            const heapClss = [];

            for (let i = 0; i < heapMem.length; i += CLS_SIZE) {
                const buffer = Buffer.from(heapMem.subarray(i, i + CLS_SIZE));
                const clsId = buffer.readUIntLE(0, 4);
                const tag = buffer.readUIntLE(4, 1);
                const data1 = buffer.readUIntLE(5, 4)
                const data2 = buffer.readUIntLE(9, 4)
                heapClss.push({ clsId, tag, data1, data2 });
            }

            console.log('Heap:');
            for (const heapCls of heapClss) {
                console.log(`  ${formatHeapCLS(heapCls)}`)
            }

            console.log(`\nStack:\n  ${stackClss.map((closureIndex, id) => formatStackFrame(heapClss, id, closureIndex))}`);
        })
)

function formatHeapCLS({ clsId, tag, data1, data2 }) {
    function formatCLS() {
        switch (tag) {
            case 0:
                return `I`
            case 1:
                return `K`
            case 2:
                return `S`
            case 3:
                return `K* ${data1}`
            case 4:
                return `S* ${data1}`
            case 5:
                return `S** ${data1} ${data2}`
        }
    }
    return `#${clsId} ${formatCLS()}`
}

function formatStackFrame (closures, id, closureIndex) {
    return `#${id} ${formatHeapCLS(closures[closureIndex])}`
}
