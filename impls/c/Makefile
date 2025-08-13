CC ?= cc
CFLAGS ?= -O3 -march=native -Wall -Wextra -std=c11
LDFLAGS ?=
BIN=bmssp_c
SRC=src/main.c

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(BIN)

.PHONY: smoke
smoke: $(BIN)
	./$(BIN) --graph grid --rows 4 --cols 4 --k 2 --B 5 --trials 1 --seed 1 --maxw 5 | head -n1 | grep '"impl"' >/dev/null
