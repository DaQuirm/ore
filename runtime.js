const fs = require('fs').promises;

const CLS_ID_TABLE = {
    0: 'I',
    1: 'K',
    2: 'S'
}

fs.readFile('./test.wasm')
    .then(buffer => WebAssembly.instantiate(buffer, { env: { log: console.log } }))
    .then(result => {
        const workingMemoryOffset = result.instance.exports.WM_ADDR.value;
        const programMem = new Uint8Array(result.instance.exports.mem.buffer, 0, workingMemoryOffset - 1);
        const stackMem = new Uint8Array(result.instance.exports.mem.buffer, workingMemoryOffset, 1024);
        const heapMem = new Uint8Array(result.instance.exports.mem.buffer, workingMemoryOffset + 1024, 13*20);
        console.log(`Program Memory: ${programMem}`);

        const stackClss = [];

        for (let i = 0; i < stackMem.length; i += 4) {
            const buffer = Buffer.from(stackMem.subarray(i, i + 4));
            const clsId = buffer.readUIntLE(0, 4);
            stackClss.push(clsId);
        }

        console.log(`Stack:\n ${stackClss.map(id => CLS_ID_TABLE[id])}`);

        const heapClss = [];

        for (let i = 0; i < heapMem.length; i += 13) {
            const buffer = Buffer.from(heapMem.subarray(i, i + 13));
            const clsId = buffer.readUIntLE(0, 4);
            const tag = buffer.readUIntLE(4, 1);
            const data1 = buffer.readUIntLE(5, 4)
            const data2 = buffer.readUIntLE(9, 4)
            heapClss.push({clsId, tag, data1, data2});
        }

        console.log('Heap:');
        for (const heapCls of heapClss) {
            console.log(formatHeapCLS(heapCls))
        }
    });


function formatHeapCLS({ clsId, tag, data1, data2 }) {
    function formatCLS () {
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
