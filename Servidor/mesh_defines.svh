/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Definiciones globales
/////////////////////////////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// Definiciones globales para el proyecto de mesh router
/////////////////////////////////////////////////////////////////////////////////////////////////////////

`ifndef MESH_DEFINES_SVH
`define MESH_DEFINES_SVH

// Parámetros del mesh
`define ROWS       4
`define COLUMNS    4
`define NUM_DEVS   16  // 2*(ROWS + COLUMNS) = 2*(4+4) = 16 dispositivos externos

// Parámetros del paquete
`define PKG_SZ     40  // Tamaño total del paquete en bits
`define PAYLOAD_W  23  // Bits de payload (40 - 8 - 4 - 4 - 1 = 23)

// Estructura del paquete (40 bits):
// [39:32] (8 bits)  - nxt_jump: Próximo salto/destino
// [31:28] (4 bits)  - target_row: Fila destino
// [27:24] (4 bits)  - target_col: Columna destino
// [23]    (1 bit)   - mode: 1=rutea primero fila, 0=rutea primero columna
// [22:0]  (23 bits) - payload: Datos del usuario

// Broadcast address
`define BROADCAST  8'hFF

// Profundidad de FIFOs
`define FIFO_DEPTH 16

`endif // MESH_DEFINES_SVH