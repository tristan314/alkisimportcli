#!/opt/homebrew/bin/bash

# ALKIS Import Wrapper for macOS
# Handles database/schema creation and overwrite protection

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verbose mode
VERBOSE=0
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
    shift
fi

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  ALKIS Import for macOS${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# FIXED: Output to stderr so it doesn't pollute command results
print_debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${YELLOW}[DEBUG] $1${NC}" >&2
    fi
}

# Check if config file provided
if [ -z "$1" ]; then
    echo "Usage: $0 [-v|--verbose] <config_file>"
    echo "Example: $0 alkis_config.txt"
    echo "         $0 -v alkis_config.txt  (verbose mode)"
    exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

print_header

if [ "$VERBOSE" -eq 1 ]; then
    print_info "Verbose mode enabled"
    echo ""
fi

# Parse config file
echo "Parsing configuration..."

# Extract database connection string
PG_LINE=$(grep -E "^PG:" "$CONFIG_FILE" | head -1)
if [ -z "$PG_LINE" ]; then
    print_error "No PG: connection string found in config"
    exit 1
fi

print_debug "PG line: $PG_LINE"

# Parse connection parameters - handle quoted and unquoted values
DB_NAME=$(echo "$PG_LINE" | grep -oE 'dbname="?[^" ]+' | sed 's/dbname=//' | tr -d '"')
DB_USER=$(echo "$PG_LINE" | grep -oE 'user="?[^" ]+' | sed 's/user=//' | tr -d '"')
DB_PASS=$(echo "$PG_LINE" | grep -oE 'password="?[^" ]+' | sed 's/password=//' | tr -d '"')
DB_HOST=$(echo "$PG_LINE" | grep -oE 'host="?[^" ]+' | sed 's/host=//' | tr -d '"')
DB_PORT=$(echo "$PG_LINE" | grep -oE 'port="?[^" ]+' | sed 's/port=//' | tr -d '"')

# Default port if not specified
DB_PORT=${DB_PORT:-5432}

# Extract schema name
SCHEMA_NAME=$(grep -E "^schema " "$CONFIG_FILE" | awk '{print $2}')
if [ -z "$SCHEMA_NAME" ]; then
    SCHEMA_NAME="public"
    print_warning "No schema specified, using 'public'"
fi

echo ""
print_info "Database: $DB_NAME"
print_info "Host: $DB_HOST:$DB_PORT"
print_info "User: $DB_USER"
print_info "Schema: $SCHEMA_NAME"
echo ""

print_debug "DB_NAME='$DB_NAME'"
print_debug "DB_USER='$DB_USER'"
print_debug "DB_HOST='$DB_HOST'"
print_debug "DB_PORT='$DB_PORT'"
print_debug "SCHEMA_NAME='$SCHEMA_NAME'"

# Build psql connection string
export PGPASSWORD="$DB_PASS"
PSQL_BASE="-h $DB_HOST -p $DB_PORT -U $DB_USER"

# Function to run psql commands
run_psql() {
    local db="$1"
    local cmd="$2"
    print_debug "Running: psql $PSQL_BASE -d \"$db\" -t -A -c \"$cmd\""
    local result
    result=$(psql $PSQL_BASE -d "$db" -t -A -c "$cmd" 2>&1)
    local exit_code=$?
    print_debug "Result: '$result' (exit code: $exit_code)"
    echo "$result"
    return $exit_code
}

run_psql_quiet() {
    local db="$1"
    local cmd="$2"
    print_debug "Running (quiet): psql $PSQL_BASE -d \"$db\" -c \"$cmd\""
    local output
    output=$(psql $PSQL_BASE -d "$db" -c "$cmd" 2>&1)
    local exit_code=$?
    print_debug "Output: $output"
    print_debug "Exit code: $exit_code"
    return $exit_code
}

# Check if database exists
echo "Checking database..."
print_debug "Checking if database '$DB_NAME' exists..."
DB_EXISTS=$(psql $PSQL_BASE -d postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null)
print_debug "DB_EXISTS result: '$DB_EXISTS'"

if [ "$DB_EXISTS" != "1" ]; then
    print_warning "Database '$DB_NAME' does not exist"
    echo ""
    read -p "Create database '$DB_NAME'? (y/n): " CREATE_DB
    
    if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
        echo "Creating database..."
        print_debug "Running: createdb $PSQL_BASE \"$DB_NAME\""
        if ! createdb $PSQL_BASE "$DB_NAME" 2>&1; then
            # Try connecting to postgres database to create
            print_debug "createdb failed, trying via psql..."
            if ! psql $PSQL_BASE -d postgres -c "CREATE DATABASE \"$DB_NAME\"" 2>&1; then
                print_error "Failed to create database. You may need superuser privileges."
                print_info "Try: createdb -h $DB_HOST -U postgres \"$DB_NAME\""
                exit 1
            fi
        fi
        print_success "Database '$DB_NAME' created"
        
        # Enable PostGIS
        echo "Enabling PostGIS extension..."
        run_psql_quiet "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS postgis;"
        print_success "PostGIS extension enabled"
    else
        print_error "Cannot proceed without database"
        exit 1
    fi
else
    print_success "Database '$DB_NAME' exists"
    
    # Check PostGIS
    POSTGIS_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM pg_extension WHERE extname='postgis'")
    if [ "$POSTGIS_EXISTS" != "1" ]; then
        print_warning "PostGIS not enabled, enabling now..."
        run_psql_quiet "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS postgis;"
        print_success "PostGIS extension enabled"
    else
        print_debug "PostGIS already enabled"
    fi
fi

# Check if schema exists
echo ""
echo "Checking schema..."
print_debug "Checking if schema '$SCHEMA_NAME' exists in database '$DB_NAME'..."
SCHEMA_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.schemata WHERE schema_name='$SCHEMA_NAME'")
print_debug "SCHEMA_EXISTS final value: '$SCHEMA_EXISTS'"

if [ "$SCHEMA_EXISTS" != "1" ]; then
    print_warning "Schema '$SCHEMA_NAME' does not exist"
    echo ""
    read -p "Create schema '$SCHEMA_NAME'? (y/n): " CREATE_SCHEMA
    
    if [[ "$CREATE_SCHEMA" =~ ^[Yy]$ ]]; then
        echo "Creating schema..."
        if ! run_psql_quiet "$DB_NAME" "CREATE SCHEMA \"$SCHEMA_NAME\";"; then
            print_error "Failed to create schema. Check permissions."
            print_info "Try: psql -h $DB_HOST -U postgres -d \"$DB_NAME\" -c \"CREATE SCHEMA $SCHEMA_NAME AUTHORIZATION $DB_USER;\""
            exit 1
        fi
        print_success "Schema '$SCHEMA_NAME' created"
        
        # Grant permissions
        echo "Setting up permissions..."
        run_psql_quiet "$DB_NAME" "GRANT ALL ON SCHEMA \"$SCHEMA_NAME\" TO \"$DB_USER\";"
        run_psql_quiet "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA \"$SCHEMA_NAME\" GRANT ALL ON TABLES TO \"$DB_USER\";"
        run_psql_quiet "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA \"$SCHEMA_NAME\" GRANT ALL ON SEQUENCES TO \"$DB_USER\";"
        print_success "Permissions configured"
    else
        print_error "Cannot proceed without schema"
        exit 1
    fi
else
    print_success "Schema '$SCHEMA_NAME' exists"
    
    # Check if schema has tables (i.e., has existing data)
    TABLE_COUNT=$(run_psql "$DB_NAME" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME'")
    print_debug "TABLE_COUNT: '$TABLE_COUNT'"
    
    # Strip whitespace and check if numeric and > 0
    TABLE_COUNT_CLEAN=$(echo "$TABLE_COUNT" | tr -d '[:space:]')
    
    if [[ "$TABLE_COUNT_CLEAN" =~ ^[0-9]+$ ]] && [ "$TABLE_COUNT_CLEAN" -gt "0" ]; then
        echo ""
        print_warning "Schema '$SCHEMA_NAME' contains $TABLE_COUNT_CLEAN tables"
        print_warning "Importing will ADD data to existing tables or FAIL on conflicts"
        echo ""
        echo "Options:"
        echo "  1) Continue anyway (append/update existing data)"
        echo "  2) Drop and recreate schema (DELETE ALL EXISTING DATA)"
        echo "  3) Cancel"
        echo ""
        read -p "Choose option (1/2/3): " SCHEMA_OPTION
        
        case $SCHEMA_OPTION in
            1)
                print_info "Continuing with existing schema..."
                ;;
            2)
                echo ""
                print_warning "WARNING: This will permanently delete ALL data in schema '$SCHEMA_NAME'"
                
                # Generate random 4-digit code
                CONFIRM_CODE=$(printf "%04d" $((RANDOM % 10000)))
                echo ""
                echo -e "${RED}To confirm deletion, enter this code: ${YELLOW}$CONFIRM_CODE${NC}"
                read -p "Enter code: " USER_CODE
                
                if [ "$USER_CODE" != "$CONFIRM_CODE" ]; then
                    print_error "Code does not match. Aborting."
                    exit 1
                fi
                
                echo ""
                echo "Dropping schema..."
                run_psql_quiet "$DB_NAME" "DROP SCHEMA \"$SCHEMA_NAME\" CASCADE;"
                print_success "Schema dropped"
                
                echo "Recreating schema..."
                run_psql_quiet "$DB_NAME" "CREATE SCHEMA \"$SCHEMA_NAME\";"
                print_success "Schema '$SCHEMA_NAME' recreated"
                
                # Grant permissions
                echo "Setting up permissions..."
                run_psql_quiet "$DB_NAME" "GRANT ALL ON SCHEMA \"$SCHEMA_NAME\" TO \"$DB_USER\";"
                run_psql_quiet "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA \"$SCHEMA_NAME\" GRANT ALL ON TABLES TO \"$DB_USER\";"
                run_psql_quiet "$DB_NAME" "ALTER DEFAULT PRIVILEGES IN SCHEMA \"$SCHEMA_NAME\" GRANT ALL ON SEQUENCES TO \"$DB_USER\";"
                print_success "Permissions configured"
                ;;
            3)
                print_info "Import cancelled"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    fi
fi

# Apply constraint fixes after import creates tables
echo ""
echo "Checking for ALKIS tables that need constraint fixes..."

# Check if ax_anschrift exists and needs fixing
AX_ANSCHRIFT_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_anschrift'")
if [ "$AX_ANSCHRIFT_EXISTS" = "1" ]; then
    CONSTRAINT_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.columns WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_anschrift' AND column_name='ort_post' AND is_nullable='NO'")
    if [ "$CONSTRAINT_EXISTS" = "1" ]; then
        echo "Relaxing constraint on ax_anschrift.ort_post..."
        run_psql_quiet "$DB_NAME" "ALTER TABLE \"$SCHEMA_NAME\".ax_anschrift ALTER COLUMN ort_post DROP NOT NULL;"
        print_success "Constraint relaxed"
    fi
fi

# Check if ax_person exists and needs fixing
AX_PERSON_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_person'")
if [ "$AX_PERSON_EXISTS" = "1" ]; then
    CONSTRAINT_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.columns WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_person' AND column_name='nachnameoderfirma' AND is_nullable='NO'")
    if [ "$CONSTRAINT_EXISTS" = "1" ]; then
        echo "Relaxing constraint on ax_person.nachnameoderfirma..."
        run_psql_quiet "$DB_NAME" "ALTER TABLE \"$SCHEMA_NAME\".ax_person ALTER COLUMN nachnameoderfirma DROP NOT NULL;"
        print_success "Constraint relaxed"
    fi
fi

# Check/create alkis_importe table
IMPORTE_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='alkis_importe'")
if [ "$IMPORTE_EXISTS" != "1" ]; then
    echo "Creating import logging table..."
    run_psql_quiet "$DB_NAME" "CREATE TABLE \"$SCHEMA_NAME\".alkis_importe (filename text, datadate text, imported_at timestamp DEFAULT now());"
    print_success "Import logging table created"
fi

# Grant permissions on all existing tables (in case schema existed)
echo ""
echo "Ensuring permissions on all tables..."
run_psql_quiet "$DB_NAME" "GRANT ALL ON ALL TABLES IN SCHEMA \"$SCHEMA_NAME\" TO \"$DB_USER\";"
run_psql_quiet "$DB_NAME" "GRANT ALL ON ALL SEQUENCES IN SCHEMA \"$SCHEMA_NAME\" TO \"$DB_USER\";"
print_success "Permissions updated"

# Ready to import
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Database setup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
print_info "Starting ALKIS import..."
echo ""

# Run the actual import script
if [ "$VERBOSE" -eq 1 ]; then
    # Run with output logging
    "$SCRIPT_DIR/alkis-import-macos.sh" "$CONFIG_FILE" 2>&1 | tee "$SCRIPT_DIR/import.log"
    IMPORT_EXIT_CODE=${PIPESTATUS[0]}
    echo ""
    print_info "Full log saved to: $SCRIPT_DIR/import.log"
else
    "$SCRIPT_DIR/alkis-import-macos.sh" "$CONFIG_FILE"
    IMPORT_EXIT_CODE=$?
fi

# Post-import: Apply constraint fixes if tables were created
echo ""
echo "Applying post-import constraint fixes..."

# Re-check and fix constraints (tables may have been created during import)
AX_ANSCHRIFT_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_anschrift'")
if [ "$AX_ANSCHRIFT_EXISTS" = "1" ]; then
    run_psql_quiet "$DB_NAME" "ALTER TABLE \"$SCHEMA_NAME\".ax_anschrift ALTER COLUMN ort_post DROP NOT NULL;" 2>/dev/null || true
fi

AX_PERSON_EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='ax_person'")
if [ "$AX_PERSON_EXISTS" = "1" ]; then
    run_psql_quiet "$DB_NAME" "ALTER TABLE \"$SCHEMA_NAME\".ax_person ALTER COLUMN nachnameoderfirma DROP NOT NULL;" 2>/dev/null || true
fi

print_success "Post-import fixes applied"

# Show summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Import Summary${NC}"
echo -e "${GREEN}========================================${NC}"
TABLE_COUNT=$(run_psql "$DB_NAME" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME'")
echo "Tables in schema '$SCHEMA_NAME': $TABLE_COUNT"

# Show row counts for main tables
echo ""
echo "Row counts for key tables:"
for table in ax_flurstueck ax_gebaeude ax_person ax_anschrift ax_buchungsblatt ax_gemarkung ax_gemeinde; do
    EXISTS=$(run_psql "$DB_NAME" "SELECT 1 FROM information_schema.tables WHERE table_schema='$SCHEMA_NAME' AND table_name='$table'")
    if [ "$EXISTS" = "1" ]; then
        COUNT=$(run_psql "$DB_NAME" "SELECT COUNT(*) FROM \"$SCHEMA_NAME\".\"$table\"")
        printf "  %-25s %s rows\n" "$table:" "$COUNT"
    fi
done

# Cleanup
unset PGPASSWORD

exit $IMPORT_EXIT_CODE