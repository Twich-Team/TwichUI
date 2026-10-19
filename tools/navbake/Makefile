# Builds navbuild against Recast fetched into .deps/ (see README.md: fetch_deps.sh pins the version).
RECAST := .deps/recastnavigation/Recast
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wno-unused-function
SRC := navbuild.cpp $(wildcard $(RECAST)/Source/*.cpp)

build/navbuild: $(SRC)
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -I$(RECAST)/Include -o $@ $(SRC)

clean:
	rm -rf build

.PHONY: clean
