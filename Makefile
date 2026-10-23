CC ?= cc
AR ?= ar
PKG_CONFIG ?= pkg-config
PREFIX ?= /usr/local
BUILD ?= build
CPPFLAGS += -Iinclude $(shell $(PKG_CONFIG) --cflags json-c)
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic -Werror -fPIC
LDLIBS += $(shell $(PKG_CONFIG) --libs json-c)
UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
SHARED = $(BUILD)/libmcp.dylib
SHARED_FLAGS = -dynamiclib -Wl,-install_name,@rpath/libmcp.dylib
else
SHARED = $(BUILD)/libmcp.so
SHARED_FLAGS = -shared -Wl,-soname,libmcp.so
endif

.PHONY: all test install clean
all: $(BUILD)/libmcp.a $(SHARED)

$(BUILD):
	mkdir -p $@

$(BUILD)/mcp.o: src/mcp.c include/mcp.h | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD)/libmcp.a: $(BUILD)/mcp.o
	$(AR) rcs $@ $<

$(SHARED): $(BUILD)/mcp.o
	$(CC) $(CFLAGS) $(LDFLAGS) $(SHARED_FLAGS) -o $@ $< $(LDLIBS)

test: all
	python3 tests/test_mcp.py $(SHARED)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) tests/client.c $(BUILD)/libmcp.a $(LDLIBS) -o $(BUILD)/c-client
	$(BUILD)/c-client "$$(command -v python3)" "$$(pwd)/tests/server.py"

install: all
	install -d $(DESTDIR)$(PREFIX)/include $(DESTDIR)$(PREFIX)/lib/pkgconfig
	install -m 644 include/mcp.h $(DESTDIR)$(PREFIX)/include/
# The archive alone: a consumer embeds the client, and -lmcp then resolves to
# it with no shared library to find at run time. The shared one is for the tests.
	install -m 644 $(BUILD)/libmcp.a $(DESTDIR)$(PREFIX)/lib/
	sed 's|@PREFIX@|$(PREFIX)|g' libmcp.pc.in > $(BUILD)/libmcp.pc
	install -m 644 $(BUILD)/libmcp.pc $(DESTDIR)$(PREFIX)/lib/pkgconfig/

clean:
	rm -rf $(BUILD)
