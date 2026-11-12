#!/usr/bin/env bash
# Script Acadêmico de Carga Senoidal para OpenArena - VERSÃO FINAL ESTÁVEL
# Inclui: Rampa de aquecimento, sintaxe correta do addbot, otimização 
# de Hunk Memory (modelo único) e rotina de limpeza automática (trap).

set -euo pipefail

# ====================================================================
# CONFIGURAÇÕES E VARIÁVEIS DE AMBIENTE
# ====================================================================
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-27960}"
export RCON_PASS="${RCON_PASS:-admin123}"

export OFFSET="${OFFSET:-45}"
export AMP="${AMP:-15}"
export PERIOD="${PERIOD:-1800}"
export MIN="${MIN:-30}"
export MAX="${MAX:-60}"
export STEP="${STEP:-15}"

echo "[INFO] Conectando ao servidor -> $HOST:$PORT"

# Desativa o controlador nativo do jogo (evita conflitos de injeção)
printf "\xff\xff\xff\xffrcon %s set bot_minplayers 0\n" "$RCON_PASS" | nc -u -w1 "$HOST" "$PORT" >/dev/null 2>&1 || true

CURRENT_BOTS=0
# CRÍTICO: Mantido apenas "sarge" para evitar estouro da Hunk Memory.
# O motor carrega a textura apenas 1 vez e clona para os 60, com nomes diferentes.
BOT_LIST=("sarge")

# ====================================================================
# FUNÇÃO DE LIMPEZA DE EMERGÊNCIA (Ctrl+C)
# ====================================================================
cleanup() {
    echo -e "\n[AVISO] Experimento abortado! Removendo os $CURRENT_BOTS bots..."
    for ((i=CURRENT_BOTS-1; i>=0; i--)); do
        printf "\xff\xff\xff\xffrcon %s kick bot_%s\n" "$RCON_PASS" "$i" | nc -u -w1 "$HOST" "$PORT" >/dev/null 2>&1 || true
        sleep 0.05
    done
    echo "[INFO] Servidor limpo com sucesso."
    exit 0
}
trap cleanup SIGINT SIGTERM

# ====================================================================
# FASE 1: AQUECIMENTO LENTO (Warm-up)
# ====================================================================
export CURRENT_T=0

# Calcula o alvo inicial da senoide
START_TARGET=$(python3 - << 'PY'
import math, os
offset = float(os.environ.get('OFFSET', 45))
amp = float(os.environ.get('AMP', 15))
period = float(os.environ.get('PERIOD', 1800))
val = offset + amp * math.sin(0)
print(int(round(val)))
PY
)

# Clamp de segurança para garantir que o start fique dentro dos limites
if [ "$START_TARGET" -lt "$MIN" ]; then START_TARGET="$MIN"; fi
if [ "$START_TARGET" -gt "$MAX" ]; then START_TARGET="$MAX"; fi

echo "[INFO] FASE DE AQUECIMENTO: Injetando $START_TARGET bots (1 por segundo)..."
for ((i=0; i<START_TARGET; i++)); do
    RANDOM_BOT=${BOT_LIST[$RANDOM % ${#BOT_LIST[@]}]}
    # CORREÇÃO CRÍTICA DE SINTAXE: addbot <nome_bot> <skill> <team> <delay> <altname>
    printf "\xff\xff\xff\xffrcon %s addbot %s 4 free 0 bot_%s\n" "$RCON_PASS" "$RANDOM_BOT" "$i" | nc -u -w1 "$HOST" "$PORT" >/dev/null 2>&1 || true
    echo " -> Injetando bot_$i ($RANDOM_BOT) ... [$((i+1))/$START_TARGET]"
    sleep 1 
done

CURRENT_BOTS=$START_TARGET
echo "[INFO] Aquecimento concluído! Servidor estável com $CURRENT_BOTS bots."
echo "[INFO] Iniciando o ciclo senoidal (Min: $MIN | Max: $MAX | Passo: ${STEP}s)..."

# ====================================================================
# FASE 2: CICLO SENOIDAL (Loop Principal)
# ====================================================================
t=0
while true; do
    export CURRENT_T="$t"

    # Cálculo da onda no instante T
    rad=$(python3 - << 'PY'
import math, os
t = float(os.environ.get('CURRENT_T', 0))
offset = float(os.environ.get('OFFSET', 45))
amp = float(os.environ.get('AMP', 15))
period = float(os.environ.get('PERIOD', 1800))
val = offset + amp * math.sin(2 * math.pi * t / period)
print(int(round(val)))
PY
)

    # Clamp dos valores da senoide
    if [ "$rad" -lt "$MIN" ]; then bots="$MIN"; elif [ "$rad" -gt "$MAX" ]; then bots="$MAX"; else bots="$rad"; fi

    # Injeção: Se a onda estiver subindo
    if [ "$bots" -gt "$CURRENT_BOTS" ]; then
        for ((i=CURRENT_BOTS; i<bots; i++)); do
            RANDOM_BOT=${BOT_LIST[$RANDOM % ${#BOT_LIST[@]}]}
            # CORREÇÃO CRÍTICA DE SINTAXE MANTIDA NO LOOP
            printf "\xff\xff\xff\xffrcon %s addbot %s 4 free 0 bot_%s\n" "$RCON_PASS" "$RANDOM_BOT" "$i" | nc -u -w1 "$HOST" "$PORT" >/dev/null 2>&1 || true
            sleep 1
        done

    # Remoção: Se a onda estiver descendo
    elif [ "$bots" -lt "$CURRENT_BOTS" ]; then
        for ((i=CURRENT_BOTS-1; i>=bots; i--)); do
            printf "\xff\xff\xff\xffrcon %s kick bot_%s\n" "$RCON_PASS" "$i" | nc -u -w1 "$HOST" "$PORT" >/dev/null 2>&1 || true
            sleep 0.2
        done
    fi

    # Atualiza o total e imprime o log do instante
    CURRENT_BOTS="$bots"
    echo "$(date '+%H:%M:%S') -> Bots no mapa: $CURRENT_BOTS (Alvo da senoide: $bots)"

    # Aguarda o intervalo (STEP) antes de recalcular
    sleep "$STEP"
    t=$((t+STEP))
done
