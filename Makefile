all: dev stable

dev:
	./run.sh

stable:
	./run.sh -m=stable

clean:
	/bin/rm -rf out-development out-stable
