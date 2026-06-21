# RSPIN---ThiLuRy

Projeto da disciplina de organização de computadores: Uma Rede SPIN, uma arquitetura de interconexão em chip (NoC) baseada em comutação de pacotes projetada para sistemas integrados escaláveis.

Este repositório contém a implementação em Verilog puro de um modelo de rede em chip (NoC) baseada na arquitetura SPIN. O projeto consiste em 8 roteadores estruturados em uma topologia fat-tree, oferecendo 32 portas de entrada e 32 portas de saída em seu nível base.

## Arquivos

### 1. Diretório `hdl/` (Hardware Description Language)

**config.vh**: Arquivo de cabeçalho (Verilog Header). Contém as diretivas `define para largura do canal (36 bits: 32 de dados + 4 de tags), constantes para os sinalizadores de enquadramento (Begin Packet - BP e End of Packet - EP), além das constantes de roteamento da árvore e bits de controle de fluxo (validação e crédito).

**fifo.v**: Implementação única de uma FIFO genérica e parametrizável. Substitui múltiplas versões de tamanho fixo, permitindo instanciar profundidades diferentes através do parâmetro DEPTH. Possui portas para leitura, escrita e sinalização de estado (full, empty).

**unidade_up.v**: Módulo UP. Conforme o diagrama interno do RSPIN, gerencia um canal de entrada superior (vindo dos pais) e um canal de saída inferior (indo para os filhos). Contém a lógica de arbitragem Round-Robin interna e instancia internamente o módulo fifo.v parametrizado com DEPTH=4.

**unidade_dn.v**: Módulo DN. Gerencia um canal de entrada inferior (vindo dos filhos) e um canal de saída superior (indo para os pais). Implementa a lógica adaptativa para escolher qual saída superior livre usar e instancia internamente o módulo fifo.v parametrizado com DEPTH=4.

**gerenciador_q.v**: Módulo que encapsula e gerencia os buffers centrais QUP (para requisições travadas subindo) e QDN (para respostas travadas descendo). Controla o fluxo baseado em créditos instanciando duas fifo.v parametrizadas com DEPTH=18.

**roteador_rspin.v**: O coração do bloco construtivo. Instancia 4 unidades unidade_up, 4 unidades unidade_dn e o gerenciador_q. Ele implementa internamente a matriz de chaves parcial (10x10 Partial Crossbar) interconectando as unidades conforme as regras de roteamento da rede SPIN.

**rede_spin_top.v**: O módulo topo do sistema. Ele instancia os 8 roteadores RSPIN e faz o mapeamento físico dos fios ponto-a-ponto entre eles. A estrutura é dividida em 4 Roteadores de 1º Nível (conectados diretamente aos terminais externos) e 4 Roteadores de 2º Nível (responsáveis pelo roteamento no topo da árvore). Este arquivo expõe para o exterior 32 interfaces de entrada e 32 de saída de dados correspondentes aos canais da base da árvore.

### 2. Diretório `test/` (Testbenches)

**tb_fifo.v**: Verifica o comportamento de leitura, escrita e as bandeiras de estado (full/empty) da FIFO genérica, testando instâncias com tamanhos diferentes (como 4 e 18).

**tb_roteador_rspin.v**: Injeta pacotes fictícios (Wormhole) em uma porta do roteador isolado e avalia se o roteamento encaminha corretamente para a saída esperada (determinística ou adaptativa).

**tb_rede_spin_top.v**: Simula um tráfego concorrente complexo (padrão pooling ou randômico) injetando dados simultaneamente pelas 32 entradas e avaliando a latência e integridade nas 32 saídas do sistema completo.

### 3. Diretórios `simulation/`, `synthesis/` e `ip/`

Atualmente mantidos na estrutura do projeto como diretórios vazios (placeholders) para organização futura, aguardando a adição de scripts de automação, arquivos de onda e eventuais blocos de IP de terceiros.

## Branchs e Fluxo de Desenvolvimento

O desenvolvimento deste projeto segue um fluxo baseado em features. Abaixo estão as branches que mapeiam o progresso de cada módulo:

- **main** (ou master): Código de produção final, estável.
- **develop**: Branch principal de integração. Todo código novo é mesclado aqui antes de ir para a versão principal.
- **feature/config-vh**: Definições de macros e parâmetros do enlace SPIN.
- **feature/fifo-generica**: Implementação da fila unificada e parametrizável.
- **feature/unidade-up**: Lógica de controle e instanciamento da via UP.
- **feature/unidade-dn**: Lógica de controle e instanciamento da via DN.
- **feature/gerenciador-q**: Implementação do controle dos buffers centrais (QUP/QDN).
- **feature/roteador-rspin**: Integração do crossbar interno e das unidades.
- **feature/rede-spin-top**: Topologia final conectando os 8 roteadores.
- **feature/testbenches**: Criação de todos os ambientes de verificação e injeção de pacotes.
