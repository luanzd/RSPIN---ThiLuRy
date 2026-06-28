// =========================================================================
// Arquivo: test/tb_fifo.v
// Descricao: Testbench AUTO-VERIFICAVEL da FIFO.
//
//   Conceito de verificacao: o proprio testbench conhece o resultado esperado,
//   compara com o que o DUT produziu, CONTA os erros e imprime um veredito no
//   final. A forma de onda (fifo.vcd) e so para depurar quando algo falha.
//
//   Cobre, no DUT de profundidade 4:
//     T0 reset            T1 encher+ordem        T2 guardas overflow/underflow
//     T3 leitura+escrita simultaneas (caso 2'b11)
//     T4 wraparound circular (ponteiros cruzam MAX_PTR e voltam a 0)
//   E, num segundo DUT de profundidade 18 (NAO potencia de 2), valida que o
//   wrap e 17->0 (e nao 31->0 do estouro binario ingenuo).
//
//   Detalhe de timing: a leitura e REGISTRADA (data_out so atualiza no ciclo
//   seguinte ao read_en). Por isso dirigimos estimulo na borda de DESCIDA e
//   conferimos data_out depois da borda de subida que efetiva a leitura.
//
//   Rode a partir da RAIZ do projeto:
//     iverilog -g2012 -o simulation/sim_fifo hdl/fifo.v test/tb_fifo.v
//     vvp simulation/sim_fifo
// =========================================================================

`timescale 1ns/1ps
`include "hdl/config.vh"

module tb_fifo;
    localparam W = `SPIN_CHANNEL_W;

    reg clk = 0, rst = 1;
    integer errors = 0;

    // ---- DUT de profundidade 4 ----
    reg              we4 = 0, re4 = 0;
    reg  [W-1:0]     din4 = 0;
    wire [W-1:0]     dout4;
    wire             full4, empty4;
    fifo #(.DEPTH(4), .WIDTH(W)) dut4 (
        .clk(clk), .rst(rst), .write_en(we4), .data_in(din4),
        .read_en(re4), .data_out(dout4), .full(full4), .empty(empty4));

    // ---- DUT de profundidade 18 (testa wrap nao-potencia-de-2) ----
    reg              we18 = 0, re18 = 0;
    reg  [W-1:0]     din18 = 0;
    wire [W-1:0]     dout18;
    wire             full18, empty18;
    fifo #(.DEPTH(18), .WIDTH(W)) dut18 (
        .clk(clk), .rst(rst), .write_en(we18), .data_in(din18),
        .read_en(re18), .data_out(dout18), .full(full18), .empty(empty18));

    always #5 clk = ~clk;

    initial begin $dumpfile("fifo.vcd"); $dumpvars(0, tb_fifo); end
    initial begin #20000 $display(">>> TIMEOUT"); $finish; end

    // ---- helpers de verificacao ----
    task chk(input [W-1:0] got, input [W-1:0] exp, input [511:0] msg);
    begin
        if (got !== exp) begin
            $display("  FALHA %0s: got=%h exp=%h @t=%0t", msg, got, exp, $time);
            errors = errors + 1;
        end else $display("  OK    %0s = %h", msg, got);
    end endtask

    task chkb(input val, input exp, input [511:0] msg);
    begin
        if (val !== exp) begin
            $display("  FALHA %0s: %b (esp %b) @t=%0t", msg, val, exp, $time);
            errors = errors + 1;
        end else $display("  OK    %0s = %b", msg, val);
    end endtask

    // ---- tarefas para o DUT de 4 ----
    task push4(input [W-1:0] d);
    begin @(negedge clk); we4 = 1; din4 = d; @(negedge clk); we4 = 0; end endtask

    task pop4(input [W-1:0] exp);
    begin @(negedge clk); re4 = 1; @(negedge clk); re4 = 0; chk(dout4, exp, "pop4"); end endtask

    task simul4(input [W-1:0] d, input [W-1:0] exp);  // escreve e le no MESMO ciclo
    begin @(negedge clk); we4 = 1; din4 = d; re4 = 1;
          @(negedge clk); we4 = 0; re4 = 0; chk(dout4, exp, "simul4"); end endtask

    integer k;
    initial begin
        repeat (2) @(negedge clk); rst = 0;

        // ---- T0: reset ----
        $display("== T0: reset ==");
        chkb(empty4, 1'b1, "empty pos-reset");
        chkb(full4,  1'b0, "full pos-reset");

        // ---- T1: encher ate 4, conferir full, drenar conferindo ORDEM ----
        $display("== T1: encher e drenar (ordem FIFO) ==");
        push4(36'h0A); push4(36'h0B); push4(36'h0C); push4(36'h0D);
        chkb(full4, 1'b1, "full apos 4 escritas");
        pop4(36'h0A); pop4(36'h0B); pop4(36'h0C); pop4(36'h0D);
        chkb(empty4, 1'b1, "empty apos drenar");

        // ---- T2: guardas. Escrita com cheia e leitura com vazia sao ignoradas ----
        $display("== T2: guardas overflow/underflow ==");
        // tenta ler vazia: nao deve dar erro nem mudar empty
        @(negedge clk); re4 = 1; @(negedge clk); re4 = 0;
        chkb(empty4, 1'b1, "continua vazia apos ler vazia");
        // enche e tenta escrever uma 5a -> deve ser ignorada (continua 4 itens)
        push4(36'h11); push4(36'h22); push4(36'h33); push4(36'h44);
        @(negedge clk); we4 = 1; din4 = 36'hFF; @(negedge clk); we4 = 0; // 5a escrita
        chkb(full4, 1'b1, "continua cheia apos overflow");
        // drena: deve sair 11,22,33,44 (a 5a foi descartada)
        pop4(36'h11); pop4(36'h22); pop4(36'h33); pop4(36'h44);
        chkb(empty4, 1'b1, "vazia apos drenar (5a descartada)");

        // ---- T3: leitura e escrita simultaneas (count constante) ----
        $display("== T3: leitura+escrita simultaneas ==");
        push4(36'd101);
        push4(36'd102);                          // FIFO: 101,102
        simul4(36'd103, 36'd101);                // escreve 103, le 101 -> 102,103
        simul4(36'd104, 36'd102);                // escreve 104, le 102 -> 103,104
        pop4(36'd103); pop4(36'd104);
        chkb(empty4, 1'b1, "vazia apos T3");

        // ---- T4: wraparound no DUT de 4 (ponteiros cruzam 3->0) ----
        $display("== T4: wraparound (DEPTH=4) ==");
        push4(36'hA1); push4(36'hA2); push4(36'hA3); // wptr: 0,1,2->3
        pop4(36'hA1);                                 // rptr: 0->1 (restam A2,A3)
        push4(36'hA4); push4(36'hA5);                 // wptr cruza 3->0->1 (A2..A5)
        pop4(36'hA2); pop4(36'hA3); pop4(36'hA4); pop4(36'hA5);
        chkb(empty4, 1'b1, "vazia apos wrap DEPTH=4");

        // ---- T5: wraparound no DUT de 18 (valida 17->0, nao 31->0) ----
        $display("== T5: wraparound (DEPTH=18, nao potencia de 2) ==");
        for (k = 0; k < 18; k = k + 1) begin
            @(negedge clk); we18 = 1; din18 = k; @(negedge clk); we18 = 0;
        end
        chkb(full18, 1'b1, "DEPTH=18 cheia apos 18 escritas");
        for (k = 0; k < 18; k = k + 1) begin
            @(negedge clk); re18 = 1; @(negedge clk); re18 = 0;
            chk(dout18, k, "drena18");
        end
        chkb(empty18, 1'b1, "DEPTH=18 vazia apos drenar");
        // agora os ponteiros estao em 0 SE o wrap for 17->0; escreve/le mais 3
        // (se o wrap fosse 31->0, estes iriam para mem[18..20] -> X)
        for (k = 0; k < 3; k = k + 1) begin
            @(negedge clk); we18 = 1; din18 = 36'd900 + k; @(negedge clk); we18 = 0;
        end
        for (k = 0; k < 3; k = k + 1) begin
            @(negedge clk); re18 = 1; @(negedge clk); re18 = 0;
            chk(dout18, 36'd900 + k, "pos-wrap18");
        end

        // ---- veredito ----
        $display("--------------------------------");
        if (errors == 0) $display(">>> TODOS OS TESTES DA FIFO PASSARAM");
        else             $display(">>> FIFO FALHOU: %0d erro(s)", errors);
        $finish;
    end
endmodule
