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
# line. Uses `od` (POSIX, unlike `xxd` which isn't installed everywhere --
# hit this on the dev machine this file was edited on) to dump hex bytes,
# then `tr -s ' ' '\n'` splits od's space-separated columns onto their own
# lines and squeezes the repeated spaces before the first column, and
# `grep -v '^$'` drops the resulting blank lines.
$(HEXOUT): $(OUTPUT)
	od -An -v -tx1 $(OUTPUT) | tr -s ' ' '\n' | grep -v '^$$' > $(HEXOUT)

clean:
	rm -f $(OUTPUT) $(HEXOUT)

.PHONY: all clean
