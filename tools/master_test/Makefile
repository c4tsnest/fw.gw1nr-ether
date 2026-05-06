SOEM_DIR := $(CURDIR)/../soem
SOEM_BUILD := $(SOEM_DIR)/build
SOEM_INC := -I$(SOEM_DIR)/include \
            -I$(SOEM_BUILD)/include \
            -I$(SOEM_DIR)/osal \
            -I$(SOEM_DIR)/osal/linux \
            -I$(SOEM_DIR)/oshw \
            -I$(SOEM_DIR)/oshw/linux

CFLAGS := -Wall -Wextra -O2 $(SOEM_INC) -D_GNU_SOURCE
LDFLAGS := -L$(SOEM_BUILD) -lsoem -lpthread -lm

.PHONY: all clean soem

all: ec_master_test

$(SOEM_BUILD)/libsoem.a: soem
	@mkdir -p $(SOEM_BUILD)
	cd $(SOEM_BUILD) && cmake .. -DCMAKE_BUILD_TYPE=Release && $(MAKE)

soem:
	@if [ ! -d "$(SOEM_DIR)/.git" ]; then \
		echo "SOEM not initialized. Run: git submodule update --init --recursive"; \
	fi

ec_master_test: $(SOEM_BUILD)/libsoem.a ec_master_test.c
	$(CC) $(CFLAGS) -o $@ ec_master_test.c $(LDFLAGS)

clean:
	rm -f ec_master_test