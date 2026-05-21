.PHONY: all clean build run run-json watch-only monitor-check monitor-install monitor-uninstall

CC := clang
CFLAGS := -O2
LDFLAGS := -L/opt/homebrew/lib $(shell pkg-config --cflags --libs libimobiledevice-1.0 libimobiledevice-glue-1.0 libplist-2.0 libusbmuxd-2.0)

SRC_DIR := src
BIN_DIR := bin
TARGET := $(BIN_DIR)/watch_battery
SOURCES := $(SRC_DIR)/watch_battery.c
IPHONE_UDID ?=
WATCH_BATTERY_AGENT_LABEL ?= com.bluetoothembedded.watch-battery-monitor
WATCH_BATTERY_AGENT_INTERVAL_SECONDS ?= 600
WATCH_BATTERY_LOW_THRESHOLD ?= 20
WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR ?= 12
WATCH_BATTERY_LOW_COOLDOWN_MINUTES ?= 30
WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES ?= 30

all: build

build: $(TARGET)

$(TARGET): $(SOURCES)
	@mkdir -p $(BIN_DIR)
	$(CC) -o $@ $< $(LDFLAGS)

run: build
	$(TARGET)

run-json: build
	$(TARGET) --json

run-watch-only: build
	$(TARGET) --watch-only

monitor-check: build
	@if [ -z "$(IPHONE_UDID)" ]; then \
		echo "Usage: make monitor-check IPHONE_UDID=<your-iphone-udid>"; \
		exit 1; \
	fi
	./scripts/watch-battery-monitor.sh --iphone $(IPHONE_UDID)

monitor-install: build
	@if [ -z "$(IPHONE_UDID)" ]; then \
		echo "Usage: make monitor-install IPHONE_UDID=<your-iphone-udid>"; \
		exit 1; \
	fi
	WATCH_BATTERY_AGENT_LABEL="$(WATCH_BATTERY_AGENT_LABEL)" \
	WATCH_BATTERY_AGENT_INTERVAL_SECONDS="$(WATCH_BATTERY_AGENT_INTERVAL_SECONDS)" \
	WATCH_BATTERY_LOW_THRESHOLD="$(WATCH_BATTERY_LOW_THRESHOLD)" \
	WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR="$(WATCH_BATTERY_FAST_DROP_RATE_PER_HOUR)" \
	WATCH_BATTERY_LOW_COOLDOWN_MINUTES="$(WATCH_BATTERY_LOW_COOLDOWN_MINUTES)" \
	WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES="$(WATCH_BATTERY_FAST_DROP_COOLDOWN_MINUTES)" \
	./scripts/install-watch-battery-agent.sh --iphone $(IPHONE_UDID)

monitor-uninstall:
	./scripts/uninstall-watch-battery-agent.sh

clean:
	rm -f $(TARGET)
