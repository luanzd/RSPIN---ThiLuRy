#!/bin/sh
# =========================================================================
# Arquivo: simulation/compile_run.sh
# Descricao: Compila e executa os testbenches da Rede SPIN com Icarus Verilog.
#
#   Uso (a partir da RAIZ do projeto):
#       sh simulation/compile_run.sh [fifo|rot|rede|all]
#   Sem argumento, roda todos.
#
#   Requer Icarus Verilog 12.0+ (flag -g2012, pois fifo.v usa cast SystemVerilog).
# =========================================================================
set -e

HDL="hdl/fifo.v hdl/unidade_up.v hdl/unidade_dn.v hdl/unidade_q.v hdl/roteador_rspin.v hdl/rede_spin_top.v"
OUT="simulation"
TARGET="${1:-all}"

run_fifo() {
  echo "=== FIFO ==="
  iverilog -g2012 -s tb_fifo -o "$OUT/sim_fifo" hdl/fifo.v test/tb_fifo.v
  vvp "$OUT/sim_fifo"
}
run_rot() {
  echo "=== ROTEADOR ==="
  iverilog -g2012 -s tb_roteador_rspin -o "$OUT/sim_rot" \
    hdl/fifo.v hdl/unidade_up.v hdl/unidade_dn.v hdl/roteador_rspin.v \
    test/tb_roteador_rspin.v
  vvp "$OUT/sim_rot"
}
run_rede() {
  echo "=== REDE ==="
  iverilog -g2012 -s tb_rede_spin_top -o "$OUT/sim_rede" $HDL test/tb_rede_spin_top.v
  vvp "$OUT/sim_rede"
}

case "$TARGET" in
fifo) run_fifo ;;
rot) run_rot ;;
rede) run_rede ;;
all)
  run_fifo
  echo
  run_rot
  echo
  run_rede
  ;;
*)
  echo "alvo invalido: $TARGET (use fifo|rot|rede|all)"
  exit 1
  ;;
esac
