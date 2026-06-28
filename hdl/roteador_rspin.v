// =========================================================================
// Arquivo: hdl/roteador_rspin.v
// Descricao: Roteador RSPIN (chave 8x8) parametrizavel pela posicao na arvore.
//
//   Estrutura interna desta versao (input-buffered wormhole):
//     - 4 unidades UP : tratam as 4 portas de ENTRADA superiores;
//     - 4 unidades DN : tratam as 4 portas de ENTRADA inferiores;
//     - um crossbar com 1 arbitro ROUND-ROBIN por canal de SAIDA (8 arbitros),
//       cada um com trava wormhole (mantem a saida reservada para o mesmo
//       pacote do header ao tail) e controle de fluxo por CREDITO;
//     - roteamento: deterministico descendo, adaptativo subindo.
//
//   Parametros:
//     NODE_LEVEL : 1 = roteador folha, 2 = roteador raiz.
//     NODE_ID    : 0..3, identificador do roteador no seu nivel.
//
//   Convencao de portas (cada porta = 2 canais unidirecionais, full-duplex):
//     up_* : 4 portas superiores (rumo aos pais)
//     dn_* : 4 portas inferiores (rumo aos filhos/terminais)
//     *_rx_*: canal de ENTRADA no roteador  (rx_cr e SAIDA: credito que devolvo)
//     *_tx_*: canal de SAIDA  do roteador   (tx_cr e ENTRADA: credito de jusante)
//   Barramentos achatados: a porta k ocupa os bits [36*k +: 36] de *_data.
//
//   NOTA DE ESCOPO (v1): os buffers centrais (unidade_q) NAO estao no datapath
//   desta versao. Um wormhole input-buffered correto nao precisa deles para
//   funcionar; eles sao a otimizacao do SPIN para desviar pacotes bloqueados
//   e evitar bloqueio de cabeca de fila. Integra-los (desviar para QUP/QDN os
//   pacotes destinados as saidas inferiores quando estas estao ocupadas) e o
//   passo "fiel ao paper" alem desta primeira versao funcional.
// =========================================================================

`include "hdl/config.vh"

// -------------------------------------------------------------------------
// Arbitro round-robin de UM canal de saida, com trava wormhole.
//   - Enquanto nao ha pacote em transito (locked=0), escolhe entre os
//     solicitantes por prioridade rotativa (rr_ptr).
//   - Ao conceder o header, trava (locked=1, lock_idx=vencedor) e so atende
//     esse solicitante ate o tail passar; entao destrava e avanca rr_ptr.
//   - So concede se houver credito a jusante (dn_credit_ok).
// -------------------------------------------------------------------------
module arbitro_rr (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] req,           // quais entradas pedem esta saida
    input  wire [7:0] tail,          // flit atual de cada entrada e o ultimo (EP)
    input  wire       dn_credit_ok,  // receptor a jusante pode aceitar
    output wire [7:0] grant,         // concessao one-hot (combinacional)
    output wire       busy           // canal reservado (locked)
);
    reg       locked;
    reg [2:0] lock_idx;
    reg [2:0] rr_ptr;

    reg [2:0] win;
    reg       win_v;
    integer   k;
    reg [2:0] idx;

    always @(*) begin
        win   = 3'd0;
        win_v = 1'b0;
        if (locked) begin
            // pacote em transito: o vencedor e sempre o dono do worm
            if (req[lock_idx]) begin win = lock_idx; win_v = 1'b1; end
        end else begin
            // sem pacote em transito: prioridade rotativa a partir de rr_ptr
            for (k = 0; k < 8; k = k + 1) begin
                idx = rr_ptr + k[2:0];
                if (!win_v && req[idx]) begin win = idx; win_v = 1'b1; end
            end
        end
    end

    wire [7:0] onehot = (8'b1 << win);
    assign grant = (win_v && dn_credit_ok) ? onehot : 8'b0;
    assign busy  = locked;

    always @(posedge clk) begin
        if (rst) begin
            locked   <= 1'b0;
            lock_idx <= 3'd0;
            rr_ptr   <= 3'd0;
        end else if (win_v && dn_credit_ok) begin
            if (!locked) begin locked <= 1'b1; lock_idx <= win; end
            if (tail[win]) begin              // ultimo flit do pacote enviado
                locked <= 1'b0;
                rr_ptr <= win + 3'd1;         // gira a prioridade
            end
        end
    end
endmodule


// -------------------------------------------------------------------------
// Roteador RSPIN
// -------------------------------------------------------------------------
module roteador_rspin #(
    parameter NODE_LEVEL = 1,
    parameter NODE_ID    = 0
) (
    input  wire clk,
    input  wire rst,

    // ---- Portas superiores (4) ----
    input  wire [4*`SPIN_CHANNEL_W-1:0] up_rx_data,
    input  wire [3:0]                   up_rx_dv,
    output wire [3:0]                   up_rx_cr,
    output wire [4*`SPIN_CHANNEL_W-1:0] up_tx_data,
    output wire [3:0]                   up_tx_dv,
    input  wire [3:0]                   up_tx_cr,

    // ---- Portas inferiores (4) ----
    input  wire [4*`SPIN_CHANNEL_W-1:0] dn_rx_data,
    input  wire [3:0]                   dn_rx_dv,
    output wire [3:0]                   dn_rx_cr,
    output wire [4*`SPIN_CHANNEL_W-1:0] dn_tx_data,
    output wire [3:0]                   dn_tx_dv,
    input  wire [3:0]                   dn_tx_cr
);
    localparam W = `SPIN_CHANNEL_W;

    // ---- Barramentos das 8 entradas para o crossbar ----
    // indices 0..3 = unidades UP (portas superiores); 4..7 = unidades DN (inferiores)
    wire         iu_req_valid [0:7];
    wire         iu_is_up     [0:7];
    wire [1:0]   iu_idx       [0:7];
    wire [W-1:0] iu_flit      [0:7];
    wire         iu_tail      [0:7];
    wire         iu_grant     [0:7];

    // ---- Concessoes e ocupacao de cada saida ----
    wire [7:0]   grant_uo [0:3];   // saidas superiores (up)
    wire [7:0]   grant_lo [0:3];   // saidas inferiores (dn)
    wire         busy_uo  [0:3];
    wire         busy_lo  [0:3];   // (nao usado externamente; saidas inf. nao sao adaptativas)

    // Mascara de saidas superiores ocupadas, entregue as unidades DN
    wire [3:0]   up_busy_vec = {busy_uo[3], busy_uo[2], busy_uo[1], busy_uo[0]};

    // ---- Vetores de requisicao por saida (montados combinacionalmente) ----
    reg  [7:0]   req_uo [0:3];
    reg  [7:0]   req_lo [0:3];
    reg  [7:0]   tail_vec;
    integer a, b;
    always @(*) begin
        for (b = 0; b < 8; b = b + 1) tail_vec[b] = iu_tail[b];
        for (a = 0; a < 4; a = a + 1) begin
            for (b = 0; b < 8; b = b + 1) begin
                req_uo[a][b] = iu_req_valid[b] &&  iu_is_up[b] && (iu_idx[b] == a[1:0]);
                req_lo[a][b] = iu_req_valid[b] && !iu_is_up[b] && (iu_idx[b] == a[1:0]);
            end
        end
    end

    // ---- Contadores de credito por saida (init = profundidade da FIFO a jusante = 4) ----
    reg [3:0] cred_uo [0:3];
    reg [3:0] cred_lo [0:3];

    genvar o, ii;

    // ---- Saidas SUPERIORES: arbitro + credito + mux do flit ----
    generate
    for (o = 0; o < 4; o = o + 1) begin: SUP
        arbitro_rr arb (
            .clk(clk), .rst(rst),
            .req(req_uo[o]), .tail(tail_vec),
            .dn_credit_ok(cred_uo[o] != 4'd0),
            .grant(grant_uo[o]), .busy(busy_uo[o])
        );
        always @(posedge clk) begin
            if (rst) cred_uo[o] <= 4'd4;
            else     cred_uo[o] <= cred_uo[o]
                                   - ((|grant_uo[o]) ? 4'd1 : 4'd0)
                                   + (up_tx_cr[o]    ? 4'd1 : 4'd0);
        end
        assign up_tx_dv[o] = |grant_uo[o];
    end
    endgenerate

    // ---- Saidas INFERIORES: arbitro + credito + mux do flit ----
    generate
    for (o = 0; o < 4; o = o + 1) begin: SLO
        arbitro_rr arb (
            .clk(clk), .rst(rst),
            .req(req_lo[o]), .tail(tail_vec),
            .dn_credit_ok(cred_lo[o] != 4'd0),
            .grant(grant_lo[o]), .busy(busy_lo[o])
        );
        always @(posedge clk) begin
            if (rst) cred_lo[o] <= 4'd4;
            else     cred_lo[o] <= cred_lo[o]
                                   - ((|grant_lo[o]) ? 4'd1 : 4'd0)
                                   + (dn_tx_cr[o]    ? 4'd1 : 4'd0);
        end
        assign dn_tx_dv[o] = |grant_lo[o];
    end
    endgenerate

    // ---- Mux dos dados de saida (flit do vencedor one-hot) ----
    integer oo, jj;
    reg [W-1:0] utx [0:3];
    reg [W-1:0] ltx [0:3];
    always @(*) begin
        for (oo = 0; oo < 4; oo = oo + 1) begin
            utx[oo] = {W{1'b0}};
            ltx[oo] = {W{1'b0}};
            for (jj = 0; jj < 8; jj = jj + 1) begin
                if (grant_uo[oo][jj]) utx[oo] = iu_flit[jj];
                if (grant_lo[oo][jj]) ltx[oo] = iu_flit[jj];
            end
        end
    end
    generate
    for (o = 0; o < 4; o = o + 1) begin: TXMAP
        assign up_tx_data[W*o +: W] = utx[o];
        assign dn_tx_data[W*o +: W] = ltx[o];
    end
    endgenerate

    // ---- Concessao de volta para cada entrada (so uma saida pode conceder) ----
    generate
    for (ii = 0; ii < 8; ii = ii + 1) begin: GR
        assign iu_grant[ii] =
            grant_uo[0][ii] | grant_uo[1][ii] | grant_uo[2][ii] | grant_uo[3][ii] |
            grant_lo[0][ii] | grant_lo[1][ii] | grant_lo[2][ii] | grant_lo[3][ii];
    end
    endgenerate

    // ---- Instancia das 4 unidades UP (entradas superiores) ----
    generate
    for (o = 0; o < 4; o = o + 1) begin: UPU
        unidade_up #(.NODE_LEVEL(NODE_LEVEL), .NODE_ID(NODE_ID)) u (
            .clk(clk), .rst(rst),
            .rx_data(up_rx_data[W*o +: W]), .rx_dv(up_rx_dv[o]), .rx_cr(up_rx_cr[o]),
            .up_busy(up_busy_vec),
            .req_valid(iu_req_valid[o]), .req_is_up(iu_is_up[o]), .req_idx(iu_idx[o]),
            .flit(iu_flit[o]), .flit_is_tail(iu_tail[o]), .grant(iu_grant[o])
        );
    end
    endgenerate

    // ---- Instancia das 4 unidades DN (entradas inferiores) ----
    generate
    for (o = 0; o < 4; o = o + 1) begin: DNU
        unidade_dn #(.NODE_LEVEL(NODE_LEVEL), .NODE_ID(NODE_ID)) u (
            .clk(clk), .rst(rst),
            .rx_data(dn_rx_data[W*o +: W]), .rx_dv(dn_rx_dv[o]), .rx_cr(dn_rx_cr[o]),
            .up_busy(up_busy_vec),
            .req_valid(iu_req_valid[4+o]), .req_is_up(iu_is_up[4+o]), .req_idx(iu_idx[4+o]),
            .flit(iu_flit[4+o]), .flit_is_tail(iu_tail[4+o]), .grant(iu_grant[4+o])
        );
    end
    endgenerate

endmodule
