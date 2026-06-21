// =========================================================================
// Arquivo: hdl/config.vh
// Descrição: Parâmetros globais, macros e definições da Rede SPIN
// =========================================================================

`ifndef CONFIG_VH
`define CONFIG_VH

// =========================================================================
// ENLACE SPIN (SPIN LINK)
// =========================================================================
// O enlace SPIN é composto por dois canais bidirecionais, permitindo
// tráfego simultâneo em ambas as direções (full-duplex).
//
// A interface física de comunicação exige 38 bits por sentido, divididos em:
// ! 32 bits: dado (payload) ou cabeçalho de roteamento
// ! 4 bits: enquadramento (BP/EP), paridade e erro (formando um canal de 36 bits)
// ! 2 bits: controle de fluxo (1 bit de validação 'dv' e 1 bit de crédito 'cr')
//
// FORMATO DO PACOTE (Comutação Wormhole):
// - A comunicação ocorre por pacotes de tamanho variável.
// - A primeira palavra (Header) ativa a flag BP e contém:
//     * Bits [31:11]: Informações do protocolo / VCI
//     * Bits [9:0]: Endereço do Destino (necessário para rotear na árvore)
// - As palavras intermediárias (Payload) carregam apenas dados brutos.
// - A última palavra do pacote ativa a flag EP (End of Packet).
// =========================================================================

// -------------------------------------------------------------------------
// Larguras dos barramentos (Canal de 36 bits de dados + tag)

// +---+---+---+---+------------------------+------+---------------+
// | x | x | 0 | 1 |   Protocolo (31-11)    | flag | Destino (9-0) |
// +---+---+---+---+------------------------+------+---------------+

// +---+---+---+---+-----------------------------------------------+
// | x | x | 0 | 0 |                 Dado (31-0)                   |
// +---+---+---+---+-----------------------------------------------+

// +---+---+---+---+-----------------------------------------------+
// | x | x | 0 | 0 |                 Dado (31-0)                   |
// +---+---+---+---+-----------------------------------------------+

//                               ...

// +---+---+---+---+-----------------------------------------------+
// | x | x | 1 | 0 |                 Dado (31-0)                   |
// +---+---+---+---+-----------------------------------------------+

`define SPIN_DATA_W     32  // Largura da carga útil (dados brutos)
`define SPIN_TAG_W      4   // Largura das flags de acompanhamento
`define SPIN_CHANNEL_W  36  // Canal principal (Dado + Tag) que viaja pelas FIFOs

// -------------------------------------------------------------------------
// Posições dos bits na TAG de 4 bits (Enquadramento, Paridade e Erro)
// -------------------------------------------------------------------------
`define TAG_BP_BIT      0   // Início de pacote (Begin Packet)
`define TAG_EP_BIT      1   // Fim de pacote (End of Packet)
`define TAG_PAR_BIT     2   // Bit de paridade
`define TAG_ERR_BIT     3   // Sinalização de erro de transmissão

// -------------------------------------------------------------------------
// Constantes de Roteamento e Formato do Cabeçalho
// -------------------------------------------------------------------------
`define ROUTE_DEST_W    10  // Largura do campo de endereço de destino (Bits 9 a 0)

//TODO: Revisar maquinas de estado e utilidade disso aqui
// -------------------------------------------------------------------------
// Estados Úteis (Opcional - para Máquinas de Estado)
// -------------------------------------------------------------------------
// Constantes lógicas para facilitar a leitura do código
`define HIGH            1'b1
`define LOW             1'b0

`endif // CONFIG_VH
