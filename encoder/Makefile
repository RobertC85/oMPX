CC=gcc
CFLAGS=-O3 -Wall -ffast-math -funroll-loops -flto -fno-signed-zeros -fno-trapping-math

all: ompx-composite

ompx-composite: ompx-composite.c composite_encoder.c
	$(CC) $(CFLAGS) -o ompx-composite ompx-composite.c composite_encoder.c -lm

clean:
	rm -f ompx-composite
