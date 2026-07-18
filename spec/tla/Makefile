TLA2TOOLS_JAR ?= $(HOME)/.local/opt/tla-toolbox/1.8.0/toolbox/tla2tools.jar
DTLA_LIB      ?= $(HOME)/.local/opt/tla-toolbox/CommunityModules/modules

export TLA2TOOLS_JAR
export DTLA_LIB

TLA_SCRIPT = $(HOME)/.local/bin/tla
TLC_EXTRA  = -deadlock

ALL_CFGS   = MaceStore.cfg MaceStoreFixed.cfg MaceStoreTargeted.cfg $(wildcard MaceStore-*.cfg)

.PHONY: all clean $(ALL_CFGS)

all: MaceStore.cfg

$(ALL_CFGS):
	$(TLA_SCRIPT) $@ $(TLC_EXTRA)

clean:
	rm -rf MaceStore.toolbox MaceStore_TTrace_*.tla states
