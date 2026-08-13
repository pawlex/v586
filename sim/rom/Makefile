# Boot ROM / test payload images for the v586 testbench.
#
#   make          - assemble boot.hex plus every tests/*.hex
#   make clean    - delete all generated .bin/.hex
#
# Each .hex is a $readmemh image the simulation loads at RUNTIME (see
# sim/README.md), so adding a test payload costs an assemble, not a
# Verilator rebuild. Drop a new tests/<name>.asm in and it is picked up
# automatically -- the pattern rule below needs no per-test edits.
#
# The generated .hex files are committed so a fresh clone can run the
# sim and the test suite without needing nasm installed.

# Configuration
NASM   = nasm
FLAGS  = -f bin
SRC    = boot.asm
OUTPUT = boot.bin
HEXOUT = boot.hex

# Test payloads: tests/*.asm -> tests/*.hex, discovered by wildcard.
TEST_SRCS := $(wildcard tests/*.asm)
TEST_BINS := $(TEST_SRCS:.asm=.bin)
TEST_HEXS := $(TEST_SRCS:.asm=.hex)

all: $(OUTPUT) $(HEXOUT) $(TEST_HEXS)

$(OUTPUT): $(SRC)
	$(NASM) $(FLAGS) $(SRC) -o $(OUTPUT)

# Generates a $readmemh-compatible hex file: one byte (two hex chars) per
# line. Uses `od` (POSIX, unlike `xxd` which isn't installed everywhere --
# hit this on the dev machine this file was edited on) to dump hex bytes,
# then `tr -s ' ' '\n'` splits od's space-separated columns onto their own
# lines and squeezes the repeated spaces before the first column, and
# `grep -v '^$'` drops the resulting blank lines.
$(HEXOUT): $(OUTPUT)
	od -An -v -tx1 $(OUTPUT) | tr -s ' ' '\n' | grep -v '^$$' > $(HEXOUT)

# Same two steps as above, as pattern rules for the test payloads.
%.bin: %.asm
	$(NASM) $(FLAGS) $< -o $@

%.hex: %.bin
	od -An -v -tx1 $< | tr -s ' ' '\n' | grep -v '^$$' > $@

# .bin is a throwaway intermediate; without this make deletes it after
# building .hex and then re-assembles it on every subsequent run.
.PRECIOUS: %.bin

clean:
	rm -f $(OUTPUT) $(HEXOUT) $(TEST_BINS) $(TEST_HEXS)

.PHONY: all clean
