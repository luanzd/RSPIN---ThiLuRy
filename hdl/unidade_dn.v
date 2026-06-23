// =========================================================================
// Arquivo: hdl/unidade_dn.v
// Descrição: Unidade DN - Gerencia o canal de entrada vindo dos filhos.
// Roteamento: UP (Adaptativo - qualquer porta) ou DOWN (Determinístico).
// =========================================================================

`include "hdl/config.vh"
`include "hdl/fifo.v"

module unidade_dn (
    input  wire clk,
    input  wire rst,

    // -----------------------------------------------------------------
    // Interface do Enlace SPIN (Vindo do roteador/terminal de baixo)
    // -----------------------------------------------------------------
    input  wire [`SPIN_DATA_W-1:0] spin_data_in,
    input  wire [`SPIN_TAG_W-1:0]  spin_tag_in,
    input  wire                    dv_in,   // Data Valid (Escreve na FIFO)
    output wire                    cr_out,  // Credit Return (Avisa que lemos)

    // -----------------------------------------------------------------
    // Interface com o Árbitro (Round-Robin) e Crossbar interno
    // -----------------------------------------------------------------
    // Pedidos (Requisições 0 ou 1)
    output reg        req_up,       // 1 = Quero subir (Qualquer porta serve)
    output reg  [3:0] req_dn,       // 1 na posição X = Quero descer pela porta X
    
    // Concessões (Grants recebidos do Árbitro)
    input  wire       gnt_up,       // Árbitro liberou uma porta de subida
    input  wire [3:0] gnt_dn,       // Árbitro liberou a porta de descida X

    // Dados enviados para o Crossbar interno
    output wire [`SPIN_CHANNEL_W-1:0] crossbar_data_out,
    output wire                       crossbar_valid_out
);

    // =================================================================
    // 1. INSTÂNCIA DA FIFO DE ENTRADA (Tamanho 4)
    // =================================================================
    wire [`SPIN_CHANNEL_W-1:0] fifo_data_in;
    wire [`SPIN_CHANNEL_W-1:0] fifo_data_out;
    wire fifo_full, fifo_empty;
    reg  fifo_read_en;

    // Concatena a Tag e o Dado para formar o Canal de 36 bits
    assign fifo_data_in = {spin_tag_in, spin_data_in};

    fifo #(
        .DEPTH(4),
        .WIDTH(`SPIN_CHANNEL_W)
    ) fifo_dn_inst (
        .clk(clk),
        .rst(rst),
        .write_en(dv_in && !fifo_full), // Só escreve se for válido e tiver espaço
        .data_in(fifo_data_in),
        .read_en(fifo_read_en),
        .data_out(fifo_data_out),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // O crédito é devolvido (pulso) toda vez que a FSM consome um dado da FIFO
    assign cr_out = fifo_read_en;

    // =================================================================
    // 2. MÁQUINA DE ESTADOS (FSM) - COMUTAÇÃO WORMHOLE
    // =================================================================
    localparam IDLE       = 2'b00; // Espera cabeçalho
    localparam WAIT_GNT   = 2'b01; // Espera o Round-Robin liberar
    localparam FORWARD    = 2'b10; // Transmite a carga útil até o fim do pacote

    reg [1:0] state, next_state;

    // Fios extraídos do dado da FIFO para facilitar a leitura
    wire is_bp = fifo_data_out[`SPIN_DATA_W + `TAG_BP_BIT]; // Bit de Início
    wire is_ep = fifo_data_out[`SPIN_DATA_W + `TAG_EP_BIT]; // Bit de Fim
    wire [`ROUTE_DEST_W-1:0] destino = fifo_data_out[`ROUTE_DEST_W-1:0]; 

    // O dado só vai para o Crossbar no estado de repasse (FORWARD)
    assign crossbar_data_out  = fifo_data_out;
    assign crossbar_valid_out = (state == FORWARD) && !fifo_empty;

    // Atualização de Estado Sequencial
    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // Lógica Combinatória da FSM e Pedidos ao Árbitro
    always @(*) begin
        // Valores padrão para evitar latches
        next_state   = state;
        fifo_read_en = 1'b0;
        req_up       = 1'b0;
        req_dn       = 4'b0000;
        //A ideia de req_dn ser 4 bits é usar o one hot:
        // 0001 - 1 
        // 0010 - 2
        // 0100 - 3 
        // 1000 - 4 
        // então a n-enésima casa do 1, representa o valor correspondente.
        // Ao em vez de 2 bits, que ia necessitar de um "wire" a mais para indicar se estava querendo usar a saida ou não.

        case (state)
            IDLE: begin
                // Se a FIFO não está vazia e o pacote tem a flag BP (Cabeçalho)
                if (!fifo_empty && is_bp) begin
                    //TODO: Para fazer os roteadores funcionarem
                    // (Aqui o roteador decidiria se o endereço pertence aos filhos dele)
                    // Vamos supor que o bit mais significativo diga se sobe (1) ou desce (0), o if abaixo é temporário
                    
                    if (destino[9] == 1'b1) begin
                        req_up = 1'b1; // Quero subir (Adaptativo)
                    end else begin
                        // Quero descer (Determinístico - ex: bits [1:0] escolhem a porta 0 a 3)
                        req_dn[destino[1:0]] = 1'b1; 
                    end
                    
                    next_state = WAIT_GNT;
                end
            end

            WAIT_GNT: begin
                // Mantém a requisição ligada até o RB conceder
                if (destino[9] == 1'b1) begin
                    req_up = 1'b1;
                    if (gnt_up) next_state = FORWARD;
                end else begin
                    req_dn[destino[1:0]] = 1'b1;
                    if (gnt_dn[destino[1:0]]) next_state = FORWARD;
                end
            end

            FORWARD: begin
                // Já temos a concessão do RB, então podemos fluir os dados
                if (!fifo_empty) begin
                    fifo_read_en = 1'b1; // Lê o dado da FIFO
                    
                    // Se for o último flit do pacote (EP), encerramos a conexão
                    if (is_ep) begin
                        next_state = IDLE;
                    end
                end
            end
        endcase
    end

endmodule