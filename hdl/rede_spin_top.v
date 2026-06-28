// =========================================================================
// Arquivo: hdl/rede_spin_top.v
// Descricao: Rede SPIN completa (SPIN16) em arvore-gorda quaternaria.
//
//   8 roteadores RSPIN, 16 terminais:
//     - 4 roteadores FOLHA  (NODE_LEVEL=1, NODE_ID 0..3): 4 portas inferiores
//       ligadas a terminais (4x4 = 16 terminais), 4 portas superiores as raizes;
//     - 4 roteadores RAIZ   (NODE_LEVEL=2, NODE_ID 0..3): 4 portas inferiores
//       ligadas as folhas (bipartido completo), 4 portas superiores LIVRES.
//
//   Ligacao bipartida: a porta superior j da folha L liga-se a porta inferior
//   L da raiz j. Assim cada folha alcanca todas as 4 raizes (4 caminhos) e cada
//   raiz alcanca todas as 4 folhas.
//
//   Enderecamento (16 terminais, 4 bits uteis do campo de 10 bits):
//     dest[3:2] = folha de destino (0..3)
//     dest[1:0] = terminal sob a folha (0..3)
//   Terminal global t = 4*folha + terminal_local.
//
//   Interface de terminal (cada terminal = 1 canal de entrada + 1 de saida):
//     ti_* : terminal -> rede (injecao).  ti_cr e SAIDA (credito p/ o terminal)
//     to_* : rede -> terminal (recepcao). to_cr e ENTRADA (credito do terminal)
//   Barramentos achatados: o terminal t ocupa [36*t +: 36] de ti_data/to_data.
// =========================================================================

`include "hdl/config.vh"

module rede_spin_top (
    input  wire clk,
    input  wire rst,

    // ---- 16 terminais: injecao na rede ----
    input  wire [16*`SPIN_CHANNEL_W-1:0] ti_data,
    input  wire [15:0]                   ti_dv,
    output wire [15:0]                   ti_cr,

    // ---- 16 terminais: recepcao da rede ----
    output wire [16*`SPIN_CHANNEL_W-1:0] to_data,
    output wire [15:0]                   to_dv,
    input  wire [15:0]                   to_cr
);
    localparam W = `SPIN_CHANNEL_W;

    // ---- Barramentos de porta de cada roteador (arrays indexados por id) ----
    // Folhas
    wire [4*W-1:0] lf_up_rx_data [0:3]; wire [3:0] lf_up_rx_dv [0:3]; wire [3:0] lf_up_rx_cr [0:3];
    wire [4*W-1:0] lf_up_tx_data [0:3]; wire [3:0] lf_up_tx_dv [0:3]; wire [3:0] lf_up_tx_cr [0:3];
    wire [4*W-1:0] lf_dn_rx_data [0:3]; wire [3:0] lf_dn_rx_dv [0:3]; wire [3:0] lf_dn_rx_cr [0:3];
    wire [4*W-1:0] lf_dn_tx_data [0:3]; wire [3:0] lf_dn_tx_dv [0:3]; wire [3:0] lf_dn_tx_cr [0:3];
    // Raizes
    wire [4*W-1:0] rt_up_rx_data [0:3]; wire [3:0] rt_up_rx_dv [0:3]; wire [3:0] rt_up_rx_cr [0:3];
    wire [4*W-1:0] rt_up_tx_data [0:3]; wire [3:0] rt_up_tx_dv [0:3]; wire [3:0] rt_up_tx_cr [0:3];
    wire [4*W-1:0] rt_dn_rx_data [0:3]; wire [3:0] rt_dn_rx_dv [0:3]; wire [3:0] rt_dn_rx_cr [0:3];
    wire [4*W-1:0] rt_dn_tx_data [0:3]; wire [3:0] rt_dn_tx_dv [0:3]; wire [3:0] rt_dn_tx_cr [0:3];

    genvar L, j, p;

    // ---- Instancia dos 4 roteadores FOLHA ----
    generate
    for (L = 0; L < 4; L = L + 1) begin: FOLHA
        roteador_rspin #(.NODE_LEVEL(1), .NODE_ID(L)) r (
            .clk(clk), .rst(rst),
            .up_rx_data(lf_up_rx_data[L]), .up_rx_dv(lf_up_rx_dv[L]), .up_rx_cr(lf_up_rx_cr[L]),
            .up_tx_data(lf_up_tx_data[L]), .up_tx_dv(lf_up_tx_dv[L]), .up_tx_cr(lf_up_tx_cr[L]),
            .dn_rx_data(lf_dn_rx_data[L]), .dn_rx_dv(lf_dn_rx_dv[L]), .dn_rx_cr(lf_dn_rx_cr[L]),
            .dn_tx_data(lf_dn_tx_data[L]), .dn_tx_dv(lf_dn_tx_dv[L]), .dn_tx_cr(lf_dn_tx_cr[L])
        );
    end
    endgenerate

    // ---- Instancia dos 4 roteadores RAIZ ----
    generate
    for (j = 0; j < 4; j = j + 1) begin: RAIZ
        roteador_rspin #(.NODE_LEVEL(2), .NODE_ID(j)) r (
            .clk(clk), .rst(rst),
            .up_rx_data(rt_up_rx_data[j]), .up_rx_dv(rt_up_rx_dv[j]), .up_rx_cr(rt_up_rx_cr[j]),
            .up_tx_data(rt_up_tx_data[j]), .up_tx_dv(rt_up_tx_dv[j]), .up_tx_cr(rt_up_tx_cr[j]),
            .dn_rx_data(rt_dn_rx_data[j]), .dn_rx_dv(rt_dn_rx_dv[j]), .dn_rx_cr(rt_dn_rx_cr[j]),
            .dn_tx_data(rt_dn_tx_data[j]), .dn_tx_dv(rt_dn_tx_dv[j]), .dn_tx_cr(rt_dn_tx_cr[j])
        );
        // Portas superiores das raizes ficam livres (topo da arvore)
        assign rt_up_rx_data[j] = {4*W{1'b0}};
        assign rt_up_rx_dv[j]   = 4'b0;
        assign rt_up_tx_cr[j]   = 4'b0;
    end
    endgenerate

    // ---- Ligacao TERMINAIS <-> portas inferiores das FOLHAS ----
    generate
    for (L = 0; L < 4; L = L + 1) begin: TLF
        for (p = 0; p < 4; p = p + 1) begin: TPORT
            // terminal global t = 4*L + p
            // injecao: terminal -> folha (porta inferior p)
            assign lf_dn_rx_data[L][W*p +: W] = ti_data[W*(4*L+p) +: W];
            assign lf_dn_rx_dv[L][p]          = ti_dv[4*L+p];
            assign ti_cr[4*L+p]               = lf_dn_rx_cr[L][p];
            // recepcao: folha -> terminal
            assign to_data[W*(4*L+p) +: W]    = lf_dn_tx_data[L][W*p +: W];
            assign to_dv[4*L+p]               = lf_dn_tx_dv[L][p];
            assign lf_dn_tx_cr[L][p]          = to_cr[4*L+p];
        end
    end
    endgenerate

    // ---- Ligacao bipartida FOLHAS <-> RAIZES ----
    // folha L, porta superior j  <->  raiz j, porta inferior L
    generate
    for (L = 0; L < 4; L = L + 1) begin: BL
        for (j = 0; j < 4; j = j + 1) begin: BJ
            // folha sobe -> raiz desce-recebe
            assign rt_dn_rx_data[j][W*L +: W] = lf_up_tx_data[L][W*j +: W];
            assign rt_dn_rx_dv[j][L]          = lf_up_tx_dv[L][j];
            assign lf_up_tx_cr[L][j]          = rt_dn_rx_cr[j][L];
            // raiz desce-envia -> folha sobe-recebe
            assign lf_up_rx_data[L][W*j +: W] = rt_dn_tx_data[j][W*L +: W];
            assign lf_up_rx_dv[L][j]          = rt_dn_tx_dv[j][L];
            assign rt_dn_tx_cr[j][L]          = lf_up_rx_cr[L][j];
        end
    end
    endgenerate

endmodule
