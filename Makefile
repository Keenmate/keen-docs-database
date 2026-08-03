.PHONY: help test test-documents setup update sql

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
	powershell.exe -File ./debee.ps1 -Operations runTests

# Run specific test suites
test-documents:
	powershell.exe -File ./debee.ps1 -Operations runTests -TestFilter documents

# Database operations (via debee.ps1)
setup:
	powershell.exe -File ./debee.ps1 -Operations fullService

update:
	powershell.exe -File ./debee.ps1 -Operations updateDatabase

# Run arbitrary SQL
sql:
	powershell.exe -File ./debee.ps1 -Operations execSql
