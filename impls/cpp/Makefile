CXX ?= c++
CXXFLAGS ?= -O3 -march=native -Wall -Wextra -std=c++20
LDFLAGS ?=
BIN=bmssp_cpp
SRC=src/main.cpp

all: $(BIN)

$(BIN): $(SRC)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(BIN)
