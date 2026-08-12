# Configuration
NASM   = nasm
FLAGS  = -f bin
SRC    = boot.asm
OUTPUT = boot.bin
HEXOUT = boot.hex

all: $(OUTPUT) $(HEXOUT)

$(OUTPUT): $(SRC)
	$(NASM) $(FLAGS) $(SRC) -o $(OUTPUT)

# Generates a $readmemh-compatible hex file: one byte (two hex chars) per
# line. Plain `xxd -p` packs ~30 bytes per line with no separators, which
# $readmemh parses as one giant multi-byte value per line instead of one
# byte per line -- `tr -d '\n' | fold -w2` flattens that and re-splits it
# cleanly on byte boundaries regardless of xxd's line width.
$(HEXOUT): $(OUTPUT)
	xxd -p $(OUTPUT) | tr -d '\n' | fold -w2 > $(HEXOUT)

clean:
	rm -f $(OUTPUT) $(HEXOUT)

.PHONY: all clean
