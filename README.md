# ALKIS Import for macOS

A macOS-compatible fork of [norGIS ALKIS Import](https://github.com/norBIT/alkisimport) for importing German cadastral data (ALKIS/NAS) into PostgreSQL/PostGIS.

## Features

- Import ALKIS/NAS XML files into PostgreSQL/PostGIS
- Generate cartographic representations following GeoInfoDok standards
- Create ownership views (`v_eigentuemer`) linking parcels to owners
- Parallel processing support for faster imports
- Progress tracking and logging

## Requirements

- **macOS** (tested on Apple Silicon)
- **PostgreSQL 14+** with PostGIS extension ([Postgres.app](https://postgresapp.com/) recommended)
- **GDAL 3.8+** with NAS driver support
- **GNU Bash 4+** (`brew install bash`)
- **GNU Parallel** (`brew install parallel`)

## Quick Start

### 1. Install Dependencies

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required packages
brew install bash parallel gdal

# Install Postgres.app from https://postgresapp.com/
```

### 2. Create Database

```bash
# Using Postgres.app's psql
/Applications/Postgres.app/Contents/Versions/17/bin/psql -c "CREATE DATABASE alkis_import;"
/Applications/Postgres.app/Contents/Versions/17/bin/psql -d alkis_import -c "CREATE EXTENSION postgis;"
```

### 3. Configure Import

Create a configuration file (e.g., `my_config.txt`):

```
# Database connection
PG:dbname=alkis_import user=your_user password=your_password host=localhost

# Schema name
schema my_schema

# Coordinate system (EPSG code)
epsg 25833

# Initialize schema (required for v_eigentuemer view)
create

# Data files to import
/path/to/your/data.xml

# Optional: parallel jobs
jobs 4
```

### 4. Run Import

```bash
# Using the wrapper script (recommended)
./alkis-import-wrapper.sh my_config.txt

# Or directly
./alkis-import-macos.sh my_config.txt
```

## Output

After a successful import, you'll have:

| Table/View | Description |
|------------|-------------|
| `ax_flurstueck` | Parcel geometries and attributes |
| `ax_person` | Owner personal data |
| `ax_anschrift` | Owner addresses |
| `ax_buchungsblatt` | Title deeds |
| `v_eigentuemer` | Combined view: parcels + owners + addresses |

## Documentation

See [DOCUMENTATION.md](DOCUMENTATION.md) for detailed information on:
- Configuration options
- Database schema
- Troubleshooting
- macOS-specific modifications

## License

GPLv2 - see [LICENSE](http://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)

## Credits

- Original project: [norBIT/alkisimport](https://github.com/norBIT/alkisimport) by Jürgen E. Fischer
- macOS adaptations and fixes: [tristan314/alkisimportcli](https://github.com/tristan314/alkisimportcli)
