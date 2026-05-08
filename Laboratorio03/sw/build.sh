#!/bin/bash
# =============================================================================
# Archivo      : sw/build.sh
# Autor        : WallyCR
# Descripcion  : Compila un programa ASM RV32I -> .elf -> .bin -> main.coe
#                Pensado para correrse desde la raiz del repo Laboratorio03.
# Uso          :
#   bash sw/build.sh                        # default: sw/asm/devid_test.s
#   bash sw/build.sh sw/asm/blink.s         # ruta directa a un .s
#   bash sw/build.sh devid_test             # nombre sin extensión (busca en sw/asm/)
# =============================================================================
set -e

# Default: programa de test del Lab 3 (lee DEVID_AD del ADXL362 -> LEDs).
DEFAULT_SRC="sw/asm/devid_test.s"
ASM_ARG="${1:-$DEFAULT_SRC}"

# Resolver el .s admitiendo:
#   - ruta directa (con o sin .s)
#   - solo el basename (busca en sw/asm/)
if [[ -f "$ASM_ARG" ]]; then
    ASM_SRC="$ASM_ARG"
elif [[ -f "${ASM_ARG}.s" ]]; then
    ASM_SRC="${ASM_ARG}.s"
elif [[ -f "sw/asm/${ASM_ARG}" ]]; then
    ASM_SRC="sw/asm/${ASM_ARG}"
elif [[ -f "sw/asm/${ASM_ARG}.s" ]]; then
    ASM_SRC="sw/asm/${ASM_ARG}.s"
else
    echo "ERROR: no encuentro '$ASM_ARG' (probé como ruta directa y bajo sw/asm/)."
    exit 1
fi

LD_SCRIPT="sw/ld/link.ld"
BUILD_DIR="sw/build"
TOOLS_DIR="sw/tools"

# Nombres derivados del basename del fuente (sin .s)
NAME="$(basename "$ASM_SRC" .s)"
OBJ="$BUILD_DIR/${NAME}.o"
ELF="$BUILD_DIR/${NAME}.elf"
BIN="$BUILD_DIR/${NAME}.bin"
COE="$BUILD_DIR/main.coe"

mkdir -p "$BUILD_DIR"

# Toolchain
TOOL=riscv64-unknown-elf

echo ">>> Compilando $ASM_SRC"
echo ">>> 1/4 Ensamblando -> $OBJ"
$TOOL-as -march=rv32i -mabi=ilp32 -o "$OBJ" "$ASM_SRC"

echo ">>> 2/4 Enlazando con $LD_SCRIPT -> $ELF"
$TOOL-ld -m elf32lriscv -T "$LD_SCRIPT" -o "$ELF" "$OBJ"

echo ">>> 3/4 Extrayendo binario plano -> $BIN"
$TOOL-objcopy -O binary "$ELF" "$BIN"

echo ">>> 4/4 Convirtiendo a .coe -> $COE"
python3 "$TOOLS_DIR/bin2coe.py" "$BIN" "$COE"

echo ""
echo "Listo. Archivos generados:"
echo "  ELF: $(realpath "$ELF")"
echo "  BIN: $(realpath "$BIN")  ($(wc -c < "$BIN") bytes)"
echo "  COE: $(realpath "$COE")"
