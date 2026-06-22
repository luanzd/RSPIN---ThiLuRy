// =========================================================================
// Arquivo: hdl/fifo.v
// Descrição: FIFO genérica circular e parametrizável para a Rede SPIN
// =========================================================================

`include "hdl/config.vh"

module fifo #(
    parameter DEPTH = 4,               // Profundidade padrão para UP/DN
    parameter WIDTH = `SPIN_CHANNEL_W  // 36 bits definido no config.vh
) (
    input wire clk,
    input wire rst,

    // Interface de Escrita
    input wire             write_en,
    input wire [WIDTH-1:0] data_in,

    // Interface de Leitura
    input  wire             read_en,
    output reg  [WIDTH-1:0] data_out,

    // Sinais de Estado
    output wire full,
    output wire empty

    //Largura dos ponteiros

);
    // Função interna do Verilog-2001 para calcular a largura dos ponteiros
    localparam PTR_WIDTH = $clog2(DEPTH);
    //Define o valor máximo do ponteiro com a largura exata
    localparam [PTR_WIDTH-1:0] MAX_PTR = PTR_WIDTH'(DEPTH - 1);
    // Array de memória
    reg [WIDTH-1:0] mem[0:DEPTH-1];

    // Ponteiros de leitura e escrita
    reg [PTR_WIDTH-1:0] rptr;
    reg [PTR_WIDTH-1:0] wptr;

    // O tamanho do contador deve acomodar o valor máximo DEPTH
    reg [PTR_WIDTH:0] count;

    // Atribuições contínuas para as flags
    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    // Bloco sequencial para controle da FIFO
    always @(posedge clk) begin
        if (rst) begin
            wptr <= 0;
            rptr <= 0;
            count <= 0;
            data_out <= 0;
        end else begin
            // ----------------------------------------------------
            // Lógica de Leitura e Escrita Simultânea
            // ----------------------------------------------------
            case ({
                write_en && !full, read_en && !empty
            })

                2'b10: begin  // Apenas Escrita
                    mem[wptr] <= data_in;
                    // Lógica circular do ponteiro
                    wptr <= (wptr == MAX_PTR) ? 0 : wptr + 1;
                    count <= count + 1;
                end

                2'b01: begin  // Apenas Leitura
                    data_out <= mem[rptr];
                    rptr <= (rptr == MAX_PTR) ? 0 : rptr + 1;
                    count <= count - 1;
                end

                2'b11: begin  // Escrita e Leitura 
                    mem[wptr] <= data_in;
                    data_out <= mem[rptr];

                    wptr <= (wptr == MAX_PTR) ? 0 : wptr + 1;
                    rptr <= (rptr == MAX_PTR) ? 0 : rptr + 1;
                    // count se mantém igual, pois entrou 1 e saiu 1
                end

                default: begin
                end
            endcase
        end
    end

endmodule
