#!/usr/bin/env ruby

require 'open-uri'
require 'icalendar'
require 'time'
require 'logger'
require 'yaml'

# === Setup Logger ===
log_path = File.join(File.dirname(__FILE__), 'hey2ical_import.log')
logger = Logger.new(log_path, 'daily')
logger.level = Logger::INFO
logger.info "Script started at #{Time.now}"

# === Configuration for multiple calendars ===
# Load calendar configs from YAML file
config_path = File.join(Dir.pwd, 'config.yml')

CALENDAR_CONFIGS = if File.exist?(config_path)
  YAML.load_file(config_path)
else
  []
end

# Validate configuration
if CALENDAR_CONFIGS.empty? || CALENDAR_CONFIGS.any? { |c| c['ics_url'].nil? }
  logger.error "No valid calendar configurations found. Please set up config.yml following config.yml.example"
  exit 1
end

CALENDAR_CONFIGS.each do |config|
  ics_url       = config['ics_url']
  calendar_name = config['calendar_name']
  logger.info "Processing calendar '#{calendar_name}' from URL: #{ics_url}"

  # === Fetch ICS data ===
  begin
    ics_data = URI.open(ics_url).read
    logger.info "Successfully fetched ICS data from #{ics_url}"
  rescue StandardError => e
    logger.error "Error fetching ICS data from #{ics_url}: #{e.message}"
    next
  end

  # === Parse ICS and collect future events ===
  begin
    calendars = Icalendar::Calendar.parse(ics_data)
    calendar_feed = calendars.first
    events = calendar_feed.events
    logger.info "Parsed ICS data: found #{events.size} events"
  rescue StandardError => e
    logger.error "Error parsing ICS data from #{ics_url}: #{e.message}"
    next
  end

  now = Time.now
  future_events = events.select do |event|
    begin
      start_time = event.dtstart
      start_time = start_time.to_time if start_time.respond_to?(:to_time)
      start_time = Time.parse(start_time.to_s) unless start_time.is_a?(Time)
      start_time = start_time.getlocal
      start_time && start_time >= now
    rescue StandardError => e
      logger.error "Error processing event start time: #{e.message}"
      false
    end
  end
  logger.info "Found #{future_events.size} future events for calendar '#{calendar_name}'"

  # === Add future events to the target Calendar (avoid duplicates) ===
  future_events.each do |event|
    begin
      title      = event.summary.to_s.strip
      start_time = event.dtstart
      end_time   = event.dtend || event.dtstart

      start_time = start_time.to_time if start_time.respond_to?(:to_time)
      start_time = Time.parse(start_time.to_s) unless start_time.is_a?(Time)
      start_time = start_time.getlocal
      end_time = end_time.to_time if end_time.respond_to?(:to_time)
      end_time = Time.parse(end_time.to_s) unless end_time.is_a?(Time)
      end_time = end_time.getlocal

      start_str = start_time.strftime("%B %d, %Y %I:%M:%S %p")
      end_str   = end_time.strftime("%B %d, %Y %I:%M:%S %p")

      # Escape any double quotes in the title for AppleScript
      title_esc = title.gsub(/"/, '\"')

      # AppleScript to add the event if it doesn't already exist
      apple_script = <<~APPLESCRIPT
        tell application "Calendar"
          tell calendar "#{calendar_name}"
            if (count of (every event whose summary is "#{title_esc}" and start date = date "#{start_str}")) = 0 then
              make new event at end of events with properties {summary:"#{title_esc}", start date:date "#{start_str}", end date:date "#{end_str}"}
            end if
          end tell
        end tell
      APPLESCRIPT

      result = system("osascript", "-e", apple_script)
      if result
        logger.info "Processed event '#{title}' at #{start_str}"
      else
        logger.error "Failed to add event '#{title}' at #{start_str}"
      end
    rescue StandardError => e
      logger.error "Error processing event '#{event.summary}': #{e.message}"
    end
  end
end

logger.info "Script finished at #{Time.now}"
