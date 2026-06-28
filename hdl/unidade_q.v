// =========================================================================
// Arquivo: hdl/unidade_q.v
// Descricao: Unidade tipo Q (buffer central) de um roteador RSPIN.
//
//   Na rede SPIN existem DOIS buffers centrais profundos (18 posicoes cada),
//   gerenciados pelas unidades QUP e QDN. Sua funcao e atacar o ponto fraco
//   do wormhole: o bloqueio de cabeca de fila (head-of-line). Quando um
//   pacote bloqueia, ele pode ser desviado para um buffer central fundo,
//   liberando a entrada para os demais pacotes. Pela regra do paper, os
//   buffers centrais so guardam pacotes destinados as SAIDAS INFERIORES.
//
//   IMPORTANTE (escopo desta versao): este modulo esta IMPLEMENTADO e
//   TESTADO isoladamente (ver test/tb_*), porem a POLITICA de desvio de
//   pacotes bloqueados para os buffers centrais NAO esta integrada ao
//   datapath do roteador nesta primeira versao (ver nota em
//   roteador_rspin.v). Aqui ele e um buffer de fluxo com controle por
//   credito em ambos os lados, pronto para essa integracao futura.
// =========================================================================

`include "hdl/config.vh"

module unidade_q #(
    parameter DEPTH            = 18,  // profundidade do buffer central
    parameter DOWN_CREDIT_INIT = 4    // creditos iniciais do receptor a jusante
) (
    input  wire                       clk,
    input  wire                       rst,

    // ---- Lado de entrada (escrita no buffer) ----
    input  wire [`SPIN_CHANNEL_W-1:0] in_data,
    input  wire                       in_dv,
    output wire                       in_cr,   // credito devolvido a montante

    // ---- Lado de saida (leitura do buffer) ----
    output wire [`SPIN_CHANNEL_W-1:0] out_data,
    output wire                       out_dv,
    input  wire                       out_cr   // credito vindo de jusante
);

    wire                       full, empty;
    wire [`SPIN_CHANNEL_W-1:0] dout;
    reg                        dout_valid;

    // Contador de creditos do receptor a jusante (quantas posicoes livres ele tem)
    reg [$clog2(DEPTH+DOWN_CREDIT_INIT+1)-1:0] down_credit;

    // Estamos enviando um flit neste ciclo?
    wire consumed = dout_valid && (down_credit != 0);

    // Le do buffer quando nada esta apresentado ou o flit apresentado foi enviado
    wire do_read = !empty && (!dout_valid || consumed);

    fifo #(.DEPTH(DEPTH), .WIDTH(`SPIN_CHANNEL_W)) buf_central (
        .clk(clk), .rst(rst),
        .write_en(in_dv), .data_in(in_data),
        .read_en(do_read), .data_out(dout),
        .full(full), .empty(empty)
    );

    assign in_cr    = do_read;     // liberei uma posicao -> devolvo credito a montante
    assign out_data = dout;
    assign out_dv   = consumed;

    always @(posedge clk) begin
        if (rst) begin
            dout_valid  <= 1'b0;
            down_credit <= DOWN_CREDIT_INIT[$clog2(DEPTH+DOWN_CREDIT_INIT+1)-1:0];
        end else begin
            if (do_read)        dout_valid <= 1'b1;
            else if (consumed)  dout_valid <= 1'b0;

            // credito: -1 ao enviar, +1 ao receber credito de jusante
            down_credit <= down_credit - (consumed ? 1'b1 : 1'b0)
                                       + (out_cr   ? 1'b1 : 1'b0);
        end
    end

endmodule
