.PHONY: help test test-documents setup update sql

# Pick the debee driver for the current platform: PowerShell on Windows, Python elsewhere.
# (debee.sh needs bash 4+ for ${VAR,,}; macOS ships bash 3.2.)
UNAME_S := $(shell uname -s)

ifneq (,$(filter MINGW% MSYS% CYGWIN%,$(UNAME_S)))
  DEBEE       = powershell.exe -File ./debee.ps1
  OP          = -Operations
  TEST_FILTER = -TestFilter
else
  DEBEE       = python3 ./debee.py
  OP          = --operations
  TEST_FILTER = --test-filter
endif

# Homebrew keg-only libpq is not on PATH by default; psql/pg_restore live there.
ifeq ($(UNAME_S),Darwin)
  LIBPQ_BIN := $(shell brew --prefix libpq 2>/dev/null)
  ifneq (,$(LIBPQ_BIN))
    export PATH := $(LIBPQ_BIN)/bin:$(PATH)
  endif
endif

# Show available targets
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Tests:"
	@echo "  test              Run all tests"
	@echo "  test-documents    Run documents app tests"
	@echo ""
	@echo "Database:"
	@echo "  setup             Full database setup (recreate + restore + update)"
	@echo "  update            Run database migrations"
	@echo "  sql               Open interactive psql session"

# Run all tests
test:
	$(DEBEE) $(OP) runTests

# Run specific test suites
test-documents:
	$(DEBEE) $(OP) runTests $(TEST_FILTER) documents

# Database operations (via debee)
setup:
	$(DEBEE) $(OP) fullService

update:
	$(DEBEE) $(OP) updateDatabase

# Run arbitrary SQL
sql:
	$(DEBEE) $(OP) execSql
