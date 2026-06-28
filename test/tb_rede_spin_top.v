// =========================================================================
// Arquivo: test/tb_rede_spin_top.v
// Descricao: Testbench AUTO-VERIFICAVEL da rede SPIN completa (SPIN16).
//
//   A) cross-leaf : term 1 (folha 0) -> term 13 (folha 3)
//   B) turnaround : term 0 -> term 3  (mesma folha 0)
//   C) concorrente: term 0 -> term 8  e  term 4 -> term 12  ao mesmo tempo
//   Em todos, verifica que chegam 3 flits NA ORDEM (header, body, tail) com
//   BP no primeiro e EP no ultimo, e o destino correto no cabecalho.
//
//   Rode a partir da RAIZ do projeto:
//     iverilog -g2012 -o simulation/sim_rede hdl/fifo.v hdl/unidade_up.v \
//       hdl/unidade_dn.v hdl/roteador_rspin.v hdl/rede_spin_top.v \
//       test/tb_rede_spin_top.v
//     vvp simulation/sim_rede
// =========================================================================

`timescale 1ns/1ps
`include "hdl/config.vh"

module tb_rede_spin_top;
    localparam W = `SPIN_CHANNEL_W;

    reg clk = 0, rst = 1;
    integer errors = 0;

    reg  [16*W-1:0] ti_data; reg [15:0] ti_dv; wire [15:0] ti_cr;
    wire [16*W-1:0] to_data; wire [15:0] to_dv; reg  [15:0] to_cr;

    rede_spin_top dut (.clk(clk), .rst(rst),
        .ti_data(ti_data), .ti_dv(ti_dv), .ti_cr(ti_cr),
        .to_data(to_data), .to_dv(to_dv), .to_cr(to_cr));

    always #5 clk = ~clk;
    initial begin #20000 $display(">>> TIMEOUT"); $finish; end

    // ---- captura por terminal (sequencia recebida) ----
    integer rxn [0:15];
    reg [W-1:0] rx_mem [0:15][0:7];
    integer i;
    always @(posedge clk) if (!rst) begin
        for (i = 0; i < 16; i = i + 1)
            if (to_dv[i] && rxn[i] < 8) begin
                rx_mem[i][rxn[i]] = to_data[W*i +: W];
                rxn[i] = rxn[i] + 1;
            end
    end

    // ---- formatadores ----
    function [W-1:0] hdr (input [9:0] d); hdr = {4'b0001, 22'd0, d}; endfunction
    localparam [W-1:0] BODY = {4'b0000, 32'hAAAA_AAAA};
    localparam [W-1:0] TAIL = {4'b0010, 32'hBBBB_BBBB};
    localparam BP_POS = `SPIN_DATA_W + `TAG_BP_BIT;
    localparam EP_POS = `SPIN_DATA_W + `TAG_EP_BIT;

    task inj(input integer term, input [W-1:0] f);
    begin ti_data[W*term +: W] = f; ti_dv[term] = 1'b1; end endtask

    // verifica que o terminal 'term' recebeu o pacote de 3 flits com destino 'd'
    task verifica(input integer term, input [9:0] d);
    begin
        if (rxn[term] != 3) begin
            $display("  FALHA: term %0d recebeu %0d flits (esp 3)", term, rxn[term]);
            errors = errors + 1;
        end else if (!rx_mem[term][0][BP_POS]) begin
            $display("  FALHA: term %0d flit 0 sem BP", term); errors = errors + 1;
        end else if (rx_mem[term][0][9:0] !== d) begin
            $display("  FALHA: term %0d destino %0d (esp %0d)", term, rx_mem[term][0][9:0], d);
            errors = errors + 1;
        end else if (rx_mem[term][1] !== BODY) begin
            $display("  FALHA: term %0d body incorreto", term); errors = errors + 1;
        end else if (!rx_mem[term][2][EP_POS]) begin
            $display("  FALHA: term %0d flit 2 sem EP", term); errors = errors + 1;
        end else
            $display("  OK: term %0d recebeu pacote completo e em ordem", term);
    end endtask

    integer c;
    initial begin
        ti_data=0; ti_dv=0; to_cr=16'hFFFF;
        for (i=0;i<16;i=i+1) rxn[i]=0;
        repeat (3) @(negedge clk); rst = 0;

        // ---- A: cross-leaf term1 -> term13 (dest=13) ----
        $display("== A: cross-leaf term1 -> term13 ==");
        @(negedge clk); inj(1, hdr(10'd13)); @(negedge clk); inj(1, BODY);
        @(negedge clk); inj(1, TAIL);        @(negedge clk); ti_dv=0;
        for (c=0;c<60;c=c+1) @(negedge clk);
        verifica(13, 10'd13);

        // ---- B: turnaround term0 -> term3 (dest=3) ----
        $display("== B: turnaround term0 -> term3 ==");
        @(negedge clk); inj(0, hdr(10'd3)); @(negedge clk); inj(0, BODY);
        @(negedge clk); inj(0, TAIL);       @(negedge clk); ti_dv=0;
        for (c=0;c<40;c=c+1) @(negedge clk);
        verifica(3, 10'd3);

        // ---- C: concorrente term0->term8 (dest=8) e term4->term12 (dest=12) ----
        $display("== C: concorrente term0->term8 e term4->term12 ==");
        @(negedge clk); inj(0, hdr(10'd8)); inj(4, hdr(10'd12));
        @(negedge clk); inj(0, BODY);       inj(4, BODY);
        @(negedge clk); inj(0, TAIL);       inj(4, TAIL);
        @(negedge clk); ti_dv=0;
        for (c=0;c<60;c=c+1) @(negedge clk);
        verifica(8,  10'd8);
        verifica(12, 10'd12);

        $display("--------------------------------");
        if (errors==0) $display(">>> REDE SPIN PASSOU em todos os cenarios");
        else           $display(">>> REDE SPIN FALHOU: %0d erro(s)", errors);
        $finish;
    end
endmodule
