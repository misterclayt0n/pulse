ODIN := odin
SRC_DIR := src
OUT := pulse
FLAGS := -out:$(OUT) -debug

all: build

build:
	@echo "Building Pulse..."
	$(ODIN) build $(SRC_DIR) $(FLAGS)

run: build
	@echo "Running $(OUT)..."
	./$(OUT)

clean:
	@echo "Cleaning up..."
	@rm -f $(OUT)

.PHONY: all build run clean
