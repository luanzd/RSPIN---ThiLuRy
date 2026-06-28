// =========================================================================
// Arquivo: hdl/unidade_up.v
// Descricao: Unidade tipo UP de um roteador RSPIN.
//
//   Convencao de nome: a unidade e nomeada pela porta de ENTRADA. A unidade
//   UP gerencia uma porta de entrada SUPERIOR (vinda de um pai) e encaminha
//   o pacote para uma saida INFERIOR (rumo a um filho). Logo: entrada em cima,
//   saida em baixo.
//
//   Como um pacote que ja esta descendo so tem um caminho ate o destino, o
//   roteamento aqui e DETERMINISTICO: o endereco de destino seleciona
//   diretamente qual saida inferior usar.
//
//   Contem:
//     - uma FIFO de entrada de 4 posicoes (instancia de fifo.v);
//     - controle de fluxo por credito no lado da entrada (rx_cr);
//     - calculo de rota (qual saida inferior) a partir do cabecalho;
//     - uma maquina wormhole que apresenta um flit por vez ao crossbar e
//       so avanca quando o crossbar concede (grant).
// =========================================================================

`include "hdl/config.vh"

module unidade_up #(
    parameter NODE_LEVEL = 1,   // 1 = roteador folha; 2 = roteador raiz
    parameter NODE_ID    = 0    // identificador (0..3) do roteador no seu nivel
) (
    input  wire                       clk,
    input  wire                       rst,

    // ---- Canal de entrada (a porta superior servida por esta unidade) ----
    input  wire [`SPIN_CHANNEL_W-1:0] rx_data,  // flit que chega
    input  wire                       rx_dv,    // flit valido neste ciclo
    output wire                       rx_cr,     // credito devolvido ao emissor

    // ---- Mascara de saidas superiores ocupadas (a UP nao usa; so a DN) ----
    input  wire [3:0]                 up_busy,

    // ---- Interface de requisicao ao crossbar ----
    output wire                       req_valid,    // tenho um flit para enviar
    output wire                       req_is_up,    // 0 = saida inferior (UP sempre desce)
    output wire [1:0]                 req_idx,      // qual saida (0..3)
    output wire [`SPIN_CHANNEL_W-1:0] flit,         // o flit apresentado
    output wire                       flit_is_tail, // o flit e o ultimo do pacote (EP)
    input  wire                       grant         // o crossbar enviou meu flit
);

    // Posicoes dos bits de enquadramento dentro do canal de 36 bits
    localparam BP_POS = `SPIN_DATA_W + `TAG_BP_BIT;  // 32
    localparam EP_POS = `SPIN_DATA_W + `TAG_EP_BIT;  // 33

    // ---- FIFO de entrada (4 posicoes) ----
    wire                       full, empty;
    wire [`SPIN_CHANNEL_W-1:0] dout;
    reg                        dout_valid;   // ha um flit valido em 'dout'

    // Le da FIFO quando: ainda nao apresentei nada, OU o flit atual foi enviado.
    wire do_read = !empty && (!dout_valid || grant);

    fifo #(.DEPTH(4), .WIDTH(`SPIN_CHANNEL_W)) buf_in (
        .clk(clk), .rst(rst),
        .write_en(rx_dv), .data_in(rx_data),  // crédito garante que nao estoura
        .read_en(do_read), .data_out(dout),
        .full(full), .empty(empty)
    );

    // Devolve 1 credito ao emissor a cada flit removido da FIFO (slot liberado)
    assign rx_cr = do_read;

    // ---- Decodificacao do flit atual ----
    wire        is_header = dout_valid && dout[BP_POS];
    wire        is_tail   = dout[EP_POS];
    wire [9:0]  dest      = dout[9:0];
    wire [1:0]  dest_leaf = dest[3:2];   // qual roteador folha (0..3)
    wire [1:0]  dest_term = dest[1:0];   // qual terminal sob a folha (0..3)

    // ---- ROTA (UP sempre desce) ----
    // Folha: a saida inferior e o terminal de destino.
    // Raiz : a saida inferior e a folha de destino.
    wire       c_is_up = 1'b0;
    wire [1:0] c_idx   = (NODE_LEVEL == 1) ? dest_term : dest_leaf;

    // Rota travada durante o pacote (do header ao tail)
    reg        route_locked;
    reg        r_is_up;
    reg [1:0]  r_idx;

    wire       pres_is_up = route_locked ? r_is_up : c_is_up;
    wire [1:0] pres_idx   = route_locked ? r_idx   : c_idx;

    assign req_is_up    = pres_is_up;
    assign req_idx      = pres_idx;
    assign flit         = dout;
    assign flit_is_tail = is_tail;
    assign req_valid    = dout_valid;  // descendo, nao depende de up_busy

    always @(posedge clk) begin
        if (rst) begin
            dout_valid   <= 1'b0;
            route_locked <= 1'b0;
            r_is_up      <= 1'b0;
            r_idx        <= 2'b0;
        end else begin
            // validade do flit apresentado
            if (do_read)    dout_valid <= 1'b1;
            else if (grant) dout_valid <= 1'b0;

            // trava/libera de rota (tail tem prioridade p/ tratar pacote de 1 flit)
            if (dout_valid && grant && dout[EP_POS]) begin
                route_locked <= 1'b0;
            end else if (!route_locked && dout_valid && dout[BP_POS]) begin
                route_locked <= 1'b1;
                r_is_up      <= c_is_up;
                r_idx        <= c_idx;
            end
        end
    end

endmodule
