GROFF ?= groff
PS2PDF ?= ps2pdf
SOURCE = rax-whitepaper.ms
PS = finished.ps
PDF = finished.pdf

.PHONY: all check clean

all: $(PDF)

$(PS): $(SOURCE)
	$(GROFF) -pet -ms -Tps $(SOURCE) > $(PS)

$(PDF): $(PS)
	$(PS2PDF) $(PS) $(PDF)

check:
	$(GROFF) -pet -ms -Tps $(SOURCE) >/dev/null

clean:
	rm -f $(PS) $(PDF)
