#!/usr/bin/env ruby

require 'open-uri'
require 'icalendar'
require 'time'
require 'logger'
require 'yaml'
require 'net/http'
require 'timeout'
require 'parallel'
require 'digest'
require 'fileutils'

# === Setup Logger ===
log_path = File.join(File.dirname(__FILE__), 'hey2ical_import.log')
$logger = Logger.new(log_path, 'daily')
$logger.level = Logger::INFO
$logger.info "Script started at #{Time.now}"

def fetch_with_retry(url, max_retries = 3, timeout = 30)
  retries = 0
  begin
    Timeout.timeout(timeout) do
      URI.open(url).read
    end
  rescue StandardError => e
    retries += 1
    if retries < max_retries
      $logger.warn "Retry #{retries}/#{max_retries} for #{url} after error: #{e.message}"
      sleep(2 ** retries) # Exponential backoff
      retry
    else
      raise
    end
  end
end

def cache_key(event)
  Digest::MD5.hexdigest("#{event.summary}#{event.dtstart}#{event.dtend}")
end

def load_cache(calendar_name)
  cache_file = File.join(Dir.pwd, '.cache', "#{calendar_name}.yml")
  File.exist?(cache_file) ? YAML.load_file(cache_file) : {}
rescue
  {}
end

def save_cache(calendar_name, cache)
  cache_dir = File.join(Dir.pwd, '.cache')
  FileUtils.mkdir_p(cache_dir)
  File.write(File.join(cache_dir, "#{calendar_name}.yml"), cache.to_yaml)
end

def execute_applescript(script)
  output = IO.popen(['osascript', '-e', script], err: [:child, :out]) { |io| io.read }
  [$?.success?, output]
end

def process_calendar(config)
  ics_url = config['ics_url']
  calendar_name = config['calendar_name']
  $logger.info "Processing calendar '#{calendar_name}' from URL: #{ics_url}"
  
  cache = load_cache(calendar_name)
  
  begin
    ics_data = fetch_with_retry(ics_url)
    $logger.info "Successfully fetched ICS data from #{ics_url}"
  rescue StandardError => e
    $logger.error "Error fetching ICS data from #{ics_url}: #{e.message}"
    return
  end

  begin
    calendars = Icalendar::Calendar.parse(ics_data)
    calendar_feed = calendars.first
    events = calendar_feed.events
    $logger.info "Parsed ICS data: found #{events.size} events"
  rescue StandardError => e
    $logger.error "Error parsing ICS data from #{ics_url}: #{e.message}"
    return
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
      $logger.error "Error processing event start time: #{e.message}"
      false
    end
  end
  
  $logger.info "Found #{future_events.size} future events for calendar '#{calendar_name}'"
  
  future_events.each do |event|
    event_cache_key = cache_key(event)
    next if cache[event_cache_key] # Skip if event is already in cache
    
    begin
      title = event.summary.to_s.strip
      start_time = event.dtstart
      end_time = event.dtend || event.dtstart

      start_time = start_time.to_time if start_time.respond_to?(:to_time)
      start_time = Time.parse(start_time.to_s) unless start_time.is_a?(Time)
      start_time = start_time.getlocal
      end_time = end_time.to_time if end_time.respond_to?(:to_time)
      end_time = Time.parse(end_time.to_s) unless end_time.is_a?(Time)
      end_time = end_time.getlocal

      start_str = start_time.strftime("%B %d, %Y %I:%M:%S %p")
      end_str = end_time.strftime("%B %d, %Y %I:%M:%S %p")

      title_esc = title.gsub(/"/, '\"')

      apple_script = <<~APPLESCRIPT
        tell application "Calendar"
          tell calendar "#{calendar_name}"
            if (count of (every event whose summary is "#{title_esc}" and start date = date "#{start_str}")) = 0 then
              make new event at end of events with properties {summary:"#{title_esc}", start date:date "#{start_str}", end date:date "#{end_str}"}
            end if
          end tell
        end tell
      APPLESCRIPT

      success, output = execute_applescript(apple_script)
      if success
        $logger.info "Processed event '#{title}' at #{start_str}"
        cache[event_cache_key] = Time.now.to_i
      else
        $logger.error "Failed to add event '#{title}' at #{start_str}: #{output}"
      end
    rescue StandardError => e
      $logger.error "Error processing event '#{event.summary}': #{e.message}"
    end
  end
  
  save_cache(calendar_name, cache)
end

# === Configuration for multiple calendars ===
config_path = File.join(Dir.pwd, 'config.yml')

CALENDAR_CONFIGS = if File.exist?(config_path)
  YAML.load_file(config_path)
else
  []
end

if CALENDAR_CONFIGS.empty? || CALENDAR_CONFIGS.any? { |c| c['ics_url'].nil? }
  $logger.error "No valid calendar configurations found. Please set up config.yml following config.yml.example"
  exit 1
end

# Process calendars in parallel
Parallel.each(CALENDAR_CONFIGS, in_threads: 4) do |config|
  process_calendar(config)
end

$logger.info "Script finished at #{Time.now}"
