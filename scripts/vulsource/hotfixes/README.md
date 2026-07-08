# Vulnerability Source Hotfixes

This directory contains static hotfix files that are bundled with fetched vulnerability data.

## Structure

```
hotfixes/
├── app-manual/
│   ├── busybox.db           # Busybox manual CVE data
│   └── tomcat.db            # Tomcat manual CVE data
├── debian/
│   ├── debian-buster.json   # Debian 10 (NVSHAS-9181)
│   └── debian-stretch.json  # Debian 9
└── README.md
```

## Usage

When a vulsource script runs (e.g., `debian.sh`), it:

1. Fetches the latest data from the upstream source
2. Checks for hotfix files in `$GITHUB_WORKSPACE/scripts/vulsource/hotfixes/<source>/`
3. Includes any found hotfix files in the final compressed output

## Adding Hotfixes

1. Place the hotfix file in the appropriate subdirectory (e.g., `debian/my-fix.json`)
2. Update the script's `HOTFIX_FILES` array to include the filename
3. Add a comment explaining the hotfix (issue number, date, purpose)

## Why Hotfixes?

These files address:
- Historical data no longer available upstream
- Urgent patches before upstream updates
- Custom entries for internal use cases
