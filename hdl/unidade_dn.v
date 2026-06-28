// =========================================================================
// Arquivo: hdl/unidade_dn.v
// Descricao: Unidade tipo DN de um roteador RSPIN.
//
//   Convencao de nome: a unidade DN gerencia uma porta de entrada INFERIOR
//   (vinda de um filho/terminal) e normalmente encaminha o pacote para uma
//   saida SUPERIOR (rumo a um pai). Ou seja: entrada em baixo, saida em cima.
//   (O nome "DN" se refere ao lado da ENTRADA, que e inferior.)
//
//   Roteamento (depende do nivel do roteador):
//     - Roteador FOLHA (NODE_LEVEL=1):
//         * se o destino esta sob ESTA folha (dest_leaf == NODE_ID) -> volta
//           para baixo (turnaround): saida inferior = terminal de destino;
//         * senao -> sobe de forma ADAPTATIVA: escolhe a MENOR saida superior
//           livre (campo up_busy informado pelo roteador). Como as 4 raizes
//           sao equivalentes, qualquer caminho livre serve.
//     - Roteador RAIZ (NODE_LEVEL=2):
//         * sempre desce: a saida inferior e a folha de destino. (Um pacote
//           na raiz ja subiu o suficiente; agora so desce.)
//
//   Contem FIFO de 4 posicoes, credito de entrada e a mesma maquina wormhole
//   da unidade UP (apresenta um flit por vez; avanca no grant).
// =========================================================================

`include "hdl/config.vh"

module unidade_dn #(
    parameter NODE_LEVEL = 1,
    parameter NODE_ID    = 0
) (
    input  wire                       clk,
    input  wire                       rst,

    // ---- Canal de entrada (a porta inferior servida por esta unidade) ----
    input  wire [`SPIN_CHANNEL_W-1:0] rx_data,
    input  wire                       rx_dv,
    output wire                       rx_cr,

    // ---- Mascara de saidas superiores ocupadas (para o roteamento adaptativo) ----
    input  wire [3:0]                 up_busy,

    // ---- Interface de requisicao ao crossbar ----
    output wire                       req_valid,
    output wire                       req_is_up,    // 1 = sobe; 0 = desce
    output wire [1:0]                 req_idx,
    output wire [`SPIN_CHANNEL_W-1:0] flit,
    output wire                       flit_is_tail,
    input  wire                       grant
);

    localparam BP_POS = `SPIN_DATA_W + `TAG_BP_BIT;
    localparam EP_POS = `SPIN_DATA_W + `TAG_EP_BIT;

    // ---- FIFO de entrada (4 posicoes) ----
    wire                       full, empty;
    wire [`SPIN_CHANNEL_W-1:0] dout;
    reg                        dout_valid;

    wire do_read = !empty && (!dout_valid || grant);

    fifo #(.DEPTH(4), .WIDTH(`SPIN_CHANNEL_W)) buf_in (
        .clk(clk), .rst(rst),
        .write_en(rx_dv), .data_in(rx_data),
        .read_en(do_read), .data_out(dout),
        .full(full), .empty(empty)
    );

    assign rx_cr = do_read;

    // ---- Decodificacao ----
    wire        is_header = dout_valid && dout[BP_POS];
    wire        is_tail   = dout[EP_POS];
    wire [9:0]  dest      = dout[9:0];
    wire [1:0]  dest_leaf = dest[3:2];
    wire [1:0]  dest_term = dest[1:0];

    // ---- ROTA ----
    wire turn    = (NODE_LEVEL == 1) && (dest_leaf == NODE_ID); // mesmo leaf -> desce
    wire at_root = (NODE_LEVEL == 2);                            // raiz -> desce
    wire go_down = turn || at_root;

    // Indice se descendo (deterministico)
    wire [1:0] down_idx = (NODE_LEVEL == 2) ? dest_leaf : dest_term;

    // Indice se subindo (adaptativo): menor saida superior livre
    wire [1:0] free_up_idx = !up_busy[0] ? 2'd0 :
                             !up_busy[1] ? 2'd1 :
                             !up_busy[2] ? 2'd2 : 2'd3;
    wire       has_free_up = ~(&up_busy);   // existe alguma saida superior livre

    wire       c_is_up = !go_down;
    wire [1:0] c_idx   = go_down ? down_idx : free_up_idx;

    // Rota travada durante o pacote
    reg        route_locked;
    reg        r_is_up;
    reg [1:0]  r_idx;

    wire       pres_is_up = route_locked ? r_is_up : c_is_up;
    wire [1:0] pres_idx   = route_locked ? r_idx   : c_idx;
    wire       going_up   = pres_is_up;

    assign req_is_up    = pres_is_up;
    assign req_idx      = pres_idx;
    assign flit         = dout;
    assign flit_is_tail = is_tail;
    // Se vou subir e ainda nao travei a rota, so peco se houver saida livre.
    // Ja travado (worm em andamento), a saida escolhida e "minha" -> sempre peco.
    assign req_valid = dout_valid && ((going_up && !route_locked) ? has_free_up : 1'b1);

    always @(posedge clk) begin
        if (rst) begin
            dout_valid   <= 1'b0;
            route_locked <= 1'b0;
            r_is_up      <= 1'b0;
            r_idx        <= 2'b0;
        end else begin
            if (do_read)    dout_valid <= 1'b1;
            else if (grant) dout_valid <= 1'b0;

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
