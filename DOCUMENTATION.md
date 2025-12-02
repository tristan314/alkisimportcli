# ALKIS Import Documentation

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Configuration Reference](#configuration-reference)
4. [Import Process](#import-process)
5. [Database Schema](#database-schema)
6. [Key Views and Tables](#key-views-and-tables)
7. [macOS Modifications](#macos-modifications)
8. [Troubleshooting](#troubleshooting)
9. [Advanced Usage](#advanced-usage)

---

## Overview

ALKIS (Amtliches Liegenschaftskatasterinformationssystem) is the official German cadastral information system. This tool imports ALKIS data delivered in NAS (Normbasierte Austauschschnittstelle) XML format into a PostgreSQL/PostGIS database.

### What Gets Imported

- **Parcels** (`ax_flurstueck`) - Land parcel geometries and attributes
- **Buildings** (`ax_gebaeude`) - Building footprints
- **Owners** (`ax_person`, `ax_namensnummer`) - Property owner information
- **Addresses** (`ax_anschrift`) - Owner addresses
- **Title Deeds** (`ax_buchungsblatt`, `ax_buchungsstelle`) - Legal ownership records
- **Administrative Units** - Districts, municipalities, cadastral districts

---

## Installation

### Prerequisites

#### PostgreSQL with PostGIS

Recommended: [Postgres.app](https://postgresapp.com/) for macOS

```bash
# After installing Postgres.app, add to PATH (optional)
export PATH="/Applications/Postgres.app/Contents/Versions/17/bin:$PATH"

# Create database
createdb alkis_import
psql -d alkis_import -c "CREATE EXTENSION postgis;"
```

#### GDAL with NAS Driver

```bash
brew install gdal

# Verify NAS driver is available
ogr2ogr --formats | grep NAS
```

#### GNU Tools

```bash
brew install bash parallel
```

### Clone Repository

```bash
git clone https://github.com/tristan314/alkisimportcli.git
cd alkisimport
chmod +x *.sh
```

---

## Configuration Reference

Create a configuration file with the following options:

### Required Options

| Option | Description | Example |
|--------|-------------|---------|
| `PG:...` | PostgreSQL connection string | `PG:dbname=alkis user=postgres host=localhost` |
| `schema` | Target schema name | `schema cadastre` |
| `epsg` | Coordinate reference system | `epsg 25833` |
| `create` | Initialize schema (required for first import) | `create` |
| Data files | Path to NAS XML files | `/path/to/data.xml` |

### Optional Options

| Option | Description | Default |
|--------|-------------|---------|
| `jobs N` | Number of parallel import jobs | 1 |
| `debug` | Enable verbose logging | disabled |

### EPSG Codes for German States

| State | UTM Zone | EPSG |
|-------|----------|------|
| Schleswig-Holstein, Hamburg, Bremen, Niedersachsen, NRW | 32 | 25832 |
| Berlin, Brandenburg, Mecklenburg-Vorpommern, Sachsen, Sachsen-Anhalt, Thüringen | 33 | 25833 |
| Bayern, Baden-Württemberg | 32 | 25832 |

### Example Configuration

```
# Database connection
PG:dbname=ALKIS_Eigentuemer user=data password=secret host=localhost

# Schema to use
schema thuringia

# Coordinate system for Thüringen
epsg 25833

# Initialize schema and create views
create

# Source data
/Users/tristan/data/alkis_export.xml

# Use 4 parallel jobs
jobs 4

# Enable debug output
debug
```

---

## Import Process

### Execution Flow

1. **Preprocessing** (`preprocessing.d/`)
   - Load signatures and symbology rules
   - Prepare duplicate handling

2. **Schema Creation** (`create` command)
   - Run `alkis-init.sql` to create base tables
   - Run `postcreate.d/` scripts including `nas2alb.sql`
   - Creates the `v_eigentuemer` view

3. **Data Import**
   - Parse NAS XML files using GDAL's NAS driver
   - Insert data into PostgreSQL via ogr2ogr

4. **Postprocessing** (`postprocessing.d/`)
   - Apply cartographic derivation rules
   - Populate ALB (Automatisiertes Liegenschaftsbuch) tables
   - Generate ownership relationships

### Running the Import

```bash
# Recommended: Use wrapper script with verbose output
./alkis-import-wrapper.sh -v config.txt

# Direct execution
./alkis-import-macos.sh config.txt
```

### Import Duration

Depends on data volume:
- Small dataset (1 municipality): 1-5 minutes
- Medium dataset (1 county): 10-30 minutes
- Large dataset (1 state): Several hours

---

## Database Schema

### Schema Organization

All tables are created in the schema specified in your config file.

```
your_schema/
├── ALKIS Base Tables (ax_*)
│   ├── ax_flurstueck          # Parcels
│   ├── ax_gebaeude            # Buildings
│   ├── ax_person              # Persons
│   ├── ax_anschrift           # Addresses
│   ├── ax_buchungsblatt       # Title deeds
│   ├── ax_buchungsstelle      # Booking entries
│   ├── ax_namensnummer        # Name numbers (ownership shares)
│   └── ...
├── ALB Tables (derived)
│   ├── flurst                 # Processed parcels
│   ├── eigner                 # Processed owners
│   ├── bestand                # Holdings
│   └── eignerart              # Ownership types
├── Views
│   ├── v_eigentuemer          # Main ownership view
│   └── v_haeuser              # Buildings view
└── Presentation Tables (ap_*)
    ├── ap_pto                 # Point presentations
    ├── ap_lto                 # Line presentations
    └── ap_ppo                 # Polygon presentations
```

---

## Key Views and Tables

### v_eigentuemer (Ownership View)

The main view combining parcels with their owners.

```sql
SELECT * FROM your_schema.v_eigentuemer LIMIT 5;
```

| Column | Type | Description |
|--------|------|-------------|
| `ogc_fid` | integer | Feature ID |
| `gml_id` | varchar | ALKIS GML identifier |
| `wkb_geometry` | geometry | Parcel geometry |
| `flsnr` | varchar | Parcel number (Flurstücksnummer) |
| `amtlflsfl` | float | Official parcel area (m²) |
| `gemarkung` | varchar | Cadastral district |
| `adressen` | text | Location description |
| `bestaende` | text | Title deed numbers |
| `eigentuemer` | text | Owner names and addresses |

### ax_flurstueck (Parcels)

```sql
SELECT
    gml_id,
    flurnummer,
    zaehler,
    nenner,
    amtlicheflaeche,
    wkb_geometry
FROM your_schema.ax_flurstueck;
```

### Ownership Chain

```
ax_flurstueck (Parcel)
    ↓ istgebucht
ax_buchungsstelle (Booking Entry)
    ↓ istbestandteilvon
ax_buchungsblatt (Title Deed)
    ↓
ax_namensnummer (Ownership Share)
    ↓ benennt
ax_person (Owner)
    ↓ hat
ax_anschrift (Address)
```

---

## macOS Modifications

This fork includes several fixes for macOS compatibility:

### Shell Script Changes

| Original (Linux) | macOS Version | File |
|------------------|---------------|------|
| `#!/bin/bash` | `#!/opt/homebrew/bin/bash` | `alkis-import-macos.sh` |
| `stat -c %s` | `stat -f %z` | `alkis-import-macos.sh` |
| `date --date="@$eta"` | `date -r "$eta"` | `alkis-import-macos.sh` |

### SQL Include Path Fixes

Changed `\i` to `\ir` (relative include) in:
- `postcreate.d/nas2alb.sql`
- `postprocessing.d/3_nas2alb.sql`
- `postinherit.d/nas2alb.sql`

This ensures `nas2alb-functions.sql` is found regardless of working directory.

### PostgreSQL 16 Compatibility

Fixed array operator syntax in postprocessing SQL files:
```sql
-- Old (PostgreSQL < 16)
ARRAY[x] <@ y

-- New (PostgreSQL 16+)
x = ANY(y)
```

---

## Troubleshooting

### Common Issues

#### "v_eigentuemer view is empty"

**Cause:** Missing `create` in config file.

**Solution:** Add `create` before your data files in the config:
```
create
/path/to/data.xml
```

#### "relation does not exist"

**Cause:** Schema not initialized.

**Solution:** Ensure `create` is in your config and the import runs the CREATE step.

#### "nas2alb-functions.sql not found"

**Cause:** Old `\i` include paths.

**Solution:** This fork has already fixed this. If you see this error, ensure you have the latest version.

#### "command not found: psql"

**Cause:** PostgreSQL not in PATH.

**Solution:**
```bash
export PATH="/Applications/Postgres.app/Contents/Versions/17/bin:$PATH"
```

Or use full path in wrapper script.

#### Permission errors on schema

**Cause:** Database user lacks permissions.

**Solution:**
```sql
GRANT ALL ON SCHEMA your_schema TO your_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA your_schema GRANT ALL ON TABLES TO your_user;
```

### Checking Import Results

```sql
-- Count key tables
SELECT 'ax_flurstueck' as table_name, count(*) FROM your_schema.ax_flurstueck
UNION ALL SELECT 'ax_person', count(*) FROM your_schema.ax_person
UNION ALL SELECT 'v_eigentuemer', count(*) FROM your_schema.v_eigentuemer;

-- Check for ownership data
SELECT flsnr, eigentuemer
FROM your_schema.v_eigentuemer
WHERE eigentuemer IS NOT NULL
LIMIT 5;
```

---

## Advanced Usage

### Importing Multiple Files

List multiple files in your config:
```
create
/path/to/file1.xml
/path/to/file2.xml
/path/to/file3.xml
```

### Importing a Directory

```
create
/path/to/nas_directory/*.xml
```

### Updating Existing Data

Remove `create` from config for subsequent imports to the same schema:
```
# No 'create' - just add/update data
/path/to/update.xml
```

### Using Different Schemas

You can import multiple datasets into separate schemas:
```bash
# First dataset
./alkis-import-wrapper.sh config_region1.txt

# Second dataset (different schema in config)
./alkis-import-wrapper.sh config_region2.txt
```

### Cleaning a Schema

To completely reset a schema:
```sql
DROP SCHEMA your_schema CASCADE;
CREATE SCHEMA your_schema;
```

Then run import with `create` again.

### Exporting Data

```bash
# Export v_eigentuemer to GeoPackage
ogr2ogr -f GPKG output.gpkg \
  "PG:dbname=alkis_import user=data" \
  -sql "SELECT * FROM your_schema.v_eigentuemer"

# Export to Shapefile
ogr2ogr -f "ESRI Shapefile" output_dir \
  "PG:dbname=alkis_import user=data" \
  -sql "SELECT * FROM your_schema.v_eigentuemer"
```

---

## References

- [ALKIS Documentation (AdV)](https://www.adv-online.de/AAA-Modell/)
- [GeoInfoDok](https://www.adv-online.de/GeoInfoDok/)
- [GDAL NAS Driver](https://gdal.org/drivers/vector/nas.html)
- [Original norGIS ALKIS Import](https://github.com/norBIT/alkisimport)
- [This fork (tristan314/alkisimportcli)](https://github.com/tristan314/alkisimportcli)
