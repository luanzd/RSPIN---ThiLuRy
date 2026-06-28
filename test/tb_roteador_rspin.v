// =========================================================================
// Arquivo: test/tb_roteador_rspin.v
// Descricao: Testbench AUTO-VERIFICAVEL de UM roteador RSPIN (folha, id 0).
//
//   Exercita os tres tipos de roteamento de uma folha:
//     A) DESCIDA deterministica  : flit entra por uma porta SUPERIOR com
//        destino a um terminal desta folha -> sai pela porta INFERIOR certa.
//     B) TURNAROUND              : flit entra por uma porta INFERIOR com
//        destino a outro terminal DESTA folha -> sai por porta INFERIOR.
//     C) SUBIDA adaptativa       : flit entra por uma porta INFERIOR com
//        destino a OUTRA folha -> sai por ALGUMA porta SUPERIOR.
//
//   Todos os canais de saida tem credito sempre disponivel (to_cr=1), pois o
//   testbench atua como sorvedouro perfeito.
//
//   Rode a partir da RAIZ do projeto:
//     iverilog -g2012 -o simulation/sim_rot hdl/fifo.v hdl/unidade_up.v \
//              hdl/unidade_dn.v hdl/roteador_rspin.v test/tb_roteador_rspin.v
//     vvp simulation/sim_rot
// =========================================================================

`timescale 1ns/1ps
`include "hdl/config.vh"

module tb_roteador_rspin;
    localparam W = `SPIN_CHANNEL_W;

    reg clk = 0, rst = 1;
    integer errors = 0;

    reg  [4*W-1:0] up_rx_data, dn_rx_data;
    reg  [3:0]     up_rx_dv,   dn_rx_dv;
    wire [3:0]     up_rx_cr,   dn_rx_cr;
    wire [4*W-1:0] up_tx_data, dn_tx_data;
    wire [3:0]     up_tx_dv,   dn_tx_dv;
    reg  [3:0]     up_tx_cr,   dn_tx_cr;

    // DUT: roteador FOLHA com id 0
    roteador_rspin #(.NODE_LEVEL(1), .NODE_ID(0)) dut (
        .clk(clk), .rst(rst),
        .up_rx_data(up_rx_data), .up_rx_dv(up_rx_dv), .up_rx_cr(up_rx_cr),
        .up_tx_data(up_tx_data), .up_tx_dv(up_tx_dv), .up_tx_cr(up_tx_cr),
        .dn_rx_data(dn_rx_data), .dn_rx_dv(dn_rx_dv), .dn_rx_cr(dn_rx_cr),
        .dn_tx_data(dn_tx_data), .dn_tx_dv(dn_tx_dv), .dn_tx_cr(dn_tx_cr));

    always #5 clk = ~clk;
    initial begin #20000 $display(">>> TIMEOUT"); $finish; end

    // ---- contadores de flits por porta de saida ----
    integer dn_cnt [0:3];
    integer up_cnt [0:3];
    integer i;
    always @(posedge clk) if (!rst) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (dn_tx_dv[i]) dn_cnt[i] = dn_cnt[i] + 1;
            if (up_tx_dv[i]) up_cnt[i] = up_cnt[i] + 1;
        end
    end

    // ---- formatadores de flit ----
    function [W-1:0] hdr (input [9:0] d); hdr = {4'b0001, 22'd0, d}; endfunction
    localparam [W-1:0] BODY = {4'b0000, 32'hAAAA_AAAA};
    localparam [W-1:0] TAIL = {4'b0010, 32'hBBBB_BBBB};

    // ---- injecao de 1 flit numa porta superior / inferior ----
    task inj_up(input integer port, input [W-1:0] f);
    begin up_rx_data[W*port +: W] = f; up_rx_dv[port] = 1'b1; end endtask
    task inj_dn(input integer port, input [W-1:0] f);
    begin dn_rx_data[W*port +: W] = f; dn_rx_dv[port] = 1'b1; end endtask

    integer c, tot_up;
    initial begin
        up_rx_data=0; dn_rx_data=0; up_rx_dv=0; dn_rx_dv=0;
        up_tx_cr=4'hF; dn_tx_cr=4'hF;
        for (i=0;i<4;i=i+1) begin dn_cnt[i]=0; up_cnt[i]=0; end
        repeat (2) @(negedge clk); rst = 0;

        // ---- A) DESCIDA: entra por up port 0, destino term 2 desta folha (dest=2) ----
        $display("== A: descida -> deve sair em dn_tx[2] ==");
        @(negedge clk); inj_up(0, hdr(10'd2)); @(negedge clk); inj_up(0, BODY);
        @(negedge clk); inj_up(0, TAIL);       @(negedge clk); up_rx_dv=0;
        for (c=0;c<30;c=c+1) @(negedge clk);
        if (dn_cnt[2]==3) $display("  OK: dn_tx[2] recebeu 3 flits");
        else begin $display("  FALHA: dn_tx[2]=%0d (esp 3)", dn_cnt[2]); errors=errors+1; end
        if (dn_cnt[0]+dn_cnt[1]+dn_cnt[3]!=0) begin
            $display("  FALHA: vazou para outra porta inferior"); errors=errors+1; end

        // ---- B) TURNAROUND: entra por dn port 1, destino term 3 desta folha (dest=3) ----
        $display("== B: turnaround -> deve sair em dn_tx[3] ==");
        @(negedge clk); inj_dn(1, hdr(10'd3)); @(negedge clk); inj_dn(1, BODY);
        @(negedge clk); inj_dn(1, TAIL);       @(negedge clk); dn_rx_dv=0;
        for (c=0;c<30;c=c+1) @(negedge clk);
        if (dn_cnt[3]==3) $display("  OK: dn_tx[3] recebeu 3 flits");
        else begin $display("  FALHA: dn_tx[3]=%0d (esp 3)", dn_cnt[3]); errors=errors+1; end

        // ---- C) SUBIDA: entra por dn port 0, destino folha 2 (dest=9) ----
        $display("== C: subida adaptativa -> deve sair em ALGUMA porta superior ==");
        @(negedge clk); inj_dn(0, hdr(10'd9)); @(negedge clk); inj_dn(0, BODY);
        @(negedge clk); inj_dn(0, TAIL);       @(negedge clk); dn_rx_dv=0;
        for (c=0;c<30;c=c+1) @(negedge clk);
        tot_up = up_cnt[0]+up_cnt[1]+up_cnt[2]+up_cnt[3];
        if (tot_up==3) $display("  OK: 3 flits subiram (porta %0d)",
                                up_cnt[0]?0:up_cnt[1]?1:up_cnt[2]?2:3);
        else begin $display("  FALHA: subiram %0d flits (esp 3)", tot_up); errors=errors+1; end

        $display("--------------------------------");
        if (errors==0) $display(">>> ROTEADOR PASSOU em todos os roteamentos");
        else           $display(">>> ROTEADOR FALHOU: %0d erro(s)", errors);
        $finish;
    end
endmodule
