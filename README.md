# hey2ical

Sync HEY calendar feeds to Apple Calendar (macOS).

## Why I Made This?
HEY Calendar lacks integration with productivity tools like Reflect Notes, which only syncs with native Apple Calendar events. This script imports HEY calendar events directly into Apple Calendar, making them accessible in Reflect Notes and other tools that rely on native calendar events.

## Requirements

- Ruby
- macOS with Calendar.app
- HEY account with calendar feeds enabled

## Setup

1. Install required gems:
```bash
gem install icalendar
```

2. Configure your calendars:
1. Copy `config.yml.example` to `config.yml`
2. Update `config.yml` with your HEY calendar feed URLs and local calendar names

You can optionally specify a custom config path:
```bash
export HEY2ICAL_CONFIG="/custom/path/to/config.yml"  # Default: ./config.yml
```

## Usage

Run the script:
```bash
./hey2ical-public.rb
```

For automation, create a launchd plist in `~/Library/LaunchAgents/com.hey2ical.plist`:
```xml
<!-- EXAMPLE -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.hey2ical</string>
    <key>ProgramArguments</key>
    <array>
      <string>/path/to/.rbenv/versions/3.3.0/bin/ruby</string>
      <string>/path/to/hey2ical/hey2ical.rb</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>/path/to/hey2ical/hey2ical_import.log</string>
    <key>StandardErrorPath</key>
    <string>/path/to/hey2ical/hey2ical_import.log</string>
    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
```

Then load it with:
```bash
launchctl load ~/Library/LaunchAgents/com.hey2ical.sync.plist
```

## How it Works

1. Fetches events from HEY calendar feeds
2. Filters for future events only
3. Adds new events to local Calendar.app calendars
4. Avoids duplicates by checking event title and start time
5. Logs all actions for troubleshooting (saved to hey2ical_import.log in script directory)