# frozen_string_literal: true

#
# Scalyr Output Plugin for Fluentd
#
# Copyright (C) 2015 Scalyr, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fluent/plugin/output"
require "fluent/plugin/scalyr_exceptions"
require "fluent/plugin/scalyr_utils"
require "fluent/plugin_helper/compat_parameters"
require "json"
require "net/http"
require "net/https"
require "rbzip2"
require "stringio"
require "zlib"
require "securerandom"
require "socket"
module Scalyr
  class ScalyrOut < Fluent::Plugin::Output
    Fluent::Plugin.register_output("scalyr", self)
    helpers :compat_parameters
    helpers :event_emitter

    config_param :api_write_token, :string
    config_param :server_attributes, :hash, default: nil
    config_param :parser, :string, default: nil # Set the "parser" field to this, per event.
    config_param :use_hostname_for_serverhost, :bool, default: true
    config_param :scalyr_server, :string, default: "https://agent.scalyr.com/"
    config_param :ssl_ca_bundle_path, :string, default: nil
    config_param :ssl_verify_peer, :bool, default: true
    config_param :ssl_verify_depth, :integer, default: 5
    config_param :message_field, :string, default: "message"
    config_param :max_request_buffer, :integer, default: 5_500_000
    config_param :force_message_encoding, :string, default: nil
    config_param :replace_invalid_utf8, :bool, default: false
    config_param :compression_type, :string, default: nil # Valid options are bz2, deflate or None. Defaults to None.
    config_param :compression_level, :integer, default: 6 # An int containing the compression level of compression to use, from 1-9. Defaults to 6

    config_section :buffer do
      config_set_default :retry_max_times, 40 # try a maximum of 40 times before discarding
      config_set_default :retry_max_interval, 30 # wait a maximum of 30 seconds per retry
      config_set_default :retry_wait, 5 # wait a minimum of 5 seconds per retry
      config_set_default :flush_interval, 5 # default flush interval of 5 seconds
      config_set_default :chunk_limit_size, 2_500_000 # default chunk size of 2.5mb
      config_set_default :queue_limit_length, 1024 # default queue size of 1024
    end

    # support for version 0.14.0:
    def compat_parameters_default_chunk_key
      ""
    end

    def formatted_to_msgpack_binary
      true
    end

    def multi_workers_ready?
      true
    end

    def configure(conf)
      if conf.elements("buffer").empty?
        $log.warn "Pre 0.14.0 configuration file detected.  Please consider updating your configuration file" # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
      end

      compat_parameters_buffer(conf, default_chunk_key: "")

      super

      if @buffer.chunk_limit_size > 6_000_000
        $log.warn "Buffer chunk size is greater than 6Mb.  This may result in requests being rejected by Scalyr" # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
      end

      if @max_request_buffer > 6_000_000
        $log.warn "Maximum request buffer > 6Mb.  This may result in requests being rejected by Scalyr" # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
      end

      @message_encoding = nil
      if @force_message_encoding.to_s != ""
        begin
          @message_encoding = Encoding.find(@force_message_encoding)
          $log.debug "Forcing message encoding to '#{@force_message_encoding}'"
        rescue ArgumentError
          $log.warn "No encoding '#{@force_message_encoding}' found.  Ignoring"
        end
      end

      # evaluate any statements in string value of the server_attributes object
      if @server_attributes
        new_attributes = {}
        @server_attributes.each do |key, value|
          next unless value.is_a?(String)

          m = /^\#{(.*)}$/.match(value)
          new_attributes[key] = if m
                                  eval(m[1]) # rubocop:disable Security/Eval
                                else
                                  value
                                end
        end
        @server_attributes = new_attributes
      end

      # See if we should use the hostname as the server_attributes.serverHost
      if @use_hostname_for_serverhost

        # ensure server_attributes is not nil
        @server_attributes = {} if @server_attributes.nil?

        # only set serverHost if it doesn't currently exist in server_attributes
        # Note: Use strings rather than symbols for the key, because keys coming
        # from the config file will be strings
        unless @server_attributes.key? "serverHost"
          @server_attributes["serverHost"] = Socket.gethostname
        end
      end

      @scalyr_server << "/" unless @scalyr_server.end_with?("/")

      @add_events_uri = URI @scalyr_server + "addEvents"

      num_threads = @buffer_config.flush_thread_count

      # forcibly limit the number of threads to 1 for now, to ensure requests always have incrementing timestamps
      if num_threads > 1
        raise Fluent::ConfigError, "num_threads is currently limited to 1. You specified #{num_threads}."
      end
    end

    def start
      super
      # Generate a session id.  This will be called once for each <match> in fluent.conf that uses scalyr
      @session = SecureRandom.uuid

      $log.info "Scalyr Fluentd Plugin ID id=#{plugin_id} worker=#{fluentd_worker_id} session=#{@session}" # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
    end

    def format(tag, time, record)
      time = Fluent::Engine.now if time.nil?

      # handle timestamps that are not EventTime types
      if time.is_a?(Integer)
        time = Fluent::EventTime.new(time)
      elsif time.is_a?(Float)
        components = time.divmod 1 # get integer and decimal components
        sec = components[0].to_i
        nsec = (components[1] * 10**9).to_i
        time = Fluent::EventTime.new(sec, nsec)
      end

      if @message_field != "message"
        if record.key? @message_field
          if record.key? "message"
            $log.warn "Overwriting log record field 'message'.  You are seeing this warning because in your fluentd config file you have configured the '#{@message_field}' field to be converted to the 'message' field, but the log record already contains a field called 'message' and this is now being overwritten." # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
          end
          record["message"] = record[@message_field]
          record.delete(@message_field)
        end
      end

      if @message_encoding && record.key?("message") && record["message"]
        if @replace_invalid_utf8 && (@message_encoding == Encoding::UTF_8)
          record["message"] = record["message"].encode("UTF-8", invalid: :replace, undef: :replace, replace: "<?>").force_encoding("UTF-8") # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
        else
          record["message"].force_encoding(@message_encoding)
        end
      end
      [tag, time.sec, time.nsec, record].to_msgpack
    rescue JSON::GeneratorError
      $log.warn "Unable to format message due to JSON::GeneratorError.  Record is:\n\t#{record}"
      raise
    end

    # called by fluentd when a chunk of log messages is ready
    def write(chunk)
      $log.debug "Size of chunk is: #{chunk.size}"
      requests = build_add_events_body(chunk)
      $log.debug "Chunk split into #{requests.size} request(s)."

      requests.each_with_index {|request, index|
        $log.debug "Request #{index + 1}/#{requests.size}: #{request[:body].bytesize} bytes"
        begin
          response = post_request(@add_events_uri, request[:body])
          handle_response(response)
        rescue OpenSSL::SSL::SSLError => e
          if e.message.include? "certificate verify failed"
            $log.warn "SSL certificate verification failed.  Please make sure your certificate bundle is configured correctly and points to a valid file. You can configure this with the ssl_ca_bundle_path configuration option. The current value of ssl_ca_bundle_path is '#{@ssl_ca_bundle_path}'" # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
          end
          $log.warn e.message
          $log.warn "Discarding buffer chunk without retrying or logging to <secondary>"
        rescue Scalyr::Client4xxError => e
          $log.warn "4XX status code received for request #{index + 1}/#{requests.size}.  Discarding buffer without retrying or logging.\n\t#{response.code} - #{e.message}\n\tChunk Size: #{chunk.size}\n\tLog messages this request: #{request[:record_count]}\n\tJSON payload size: #{request[:body].bytesize}\n\tSample: #{request[:body][0, 1024]}..."
        end
      }
    rescue JSON::GeneratorError
      $log.warn "Unable to format message due to JSON::GeneratorError."
      raise
    end

    # explicit function to convert to nanoseconds
    # will make things easier to maintain if/when fluentd supports higher than second resolutions
    def to_nanos(seconds, nsec)
      (seconds * 10**9) + nsec
    end

    # explicit function to convert to milliseconds
    # will make things easier to maintain if/when fluentd supports higher than second resolutions
    def to_millis(timestamp)
      (timestamp.sec * 10**3) + (timestamp.nsec / 10**6)
    end

    def post_request(uri, body)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true

      # verify peers to prevent potential MITM attacks
      if @ssl_verify_peer
        https.ca_file = @ssl_ca_bundle_path unless @ssl_ca_bundle_path.nil?
        https.ssl_version = :TLSv1_2
        https.verify_mode = OpenSSL::SSL::VERIFY_PEER
        https.verify_depth = @ssl_verify_depth
      end

      # use compression if enabled
      encoding = nil

      if @compression_type
        if @compression_type == "deflate"
          encoding = "deflate"
          body = Zlib::Deflate.deflate(body, @compression_level)
        elsif @compression_type == "bz2"
          encoding = "bz2"
          io = StringIO.new
          bz2 = RBzip2.default_adapter::Compressor.new io
          bz2.write body
          bz2.close
          body = io.string
        end
      end

      post = Net::HTTP::Post.new uri.path
      post.add_field("Content-Type", "application/json")

      post.add_field("Content-Encoding", encoding) if @compression_type

      post.body = body

      https.request(post)
    end

    def handle_response(response)
      $log.debug "Response Code: #{response.code}"
      $log.debug "Response Body: #{response.body}"

      response_hash = {}

      begin
        response_hash = JSON.parse(response.body)
      rescue StandardError
        response_hash["status"] = "Invalid JSON response from server"
      end

      # make sure the JSON reponse has a "status" field
      unless response_hash.key? "status"
        $log.debug "JSON response does not contain status message"
        raise Scalyr::ServerError.new "JSON response does not contain status message"
      end

      status = response_hash["status"]

      # 4xx codes are handled separately
      if response.code =~ /^4\d\d/
        raise Scalyr::Client4xxError.new status
      else
        if status != "success" # rubocop:disable Style/IfInsideElse
          if status =~ /discardBuffer/
            $log.warn "Received 'discardBuffer' message from server.  Buffer dropped."
          elsif status =~ %r{/client/}i
            raise Scalyr::ClientError.new status
          else # don't check specifically for server, we assume all non-client errors are server errors
            raise Scalyr::ServerError.new status
          end
        elsif !response.code.include? "200" # response code is a string not an int
          raise Scalyr::ServerError
        end
      end
    end

    def build_add_events_body(chunk)
      # requests
      requests = []

      # set of unique scalyr threads for this chunk
      current_threads = {}

      # byte count
      total_bytes = 0

      # create a Scalyr event object for each record in the chunk
      events = []
      chunk.msgpack_each {|(tag, sec, nsec, record)| # rubocop:disable Metrics/BlockLength
        timestamp = to_nanos(sec, nsec)

        thread_id = tag

        # then update the map of threads for this chunk
        current_threads[tag] = thread_id

        # add a logfile field if one doesn't exist
        record["logfile"] = "/fluentd/#{tag}" unless record.key? "logfile"

        # set per-event parser if it is configured
        record["parser"] = @parser unless @parser.nil?

        # append to list of events
        event = {thread: thread_id.to_s,
                 ts:     timestamp,
                 attrs:  record}

        # get json string of event to keep track of how many bytes we are sending

        begin
          event_json = event.to_json
        rescue JSON::GeneratorError, Encoding::UndefinedConversionError => e
          $log.warn "JSON serialization of the event failed: #{e.class}: #{e.message}"

          # Send the faulty event to a label @ERROR block and allow to handle it there (output to exceptions file for ex)
          time = Fluent::EventTime.new(sec, nsec)
          router.emit_error_event(tag, time, record, e)

          # Print attribute values for debugging / troubleshooting purposes
          $log.debug "Event attributes:"

          event[:attrs].each do |key, value|
            # NOTE: value doesn't always value.encoding attribute so we use .class which is always available
            $log.debug "\t#{key} (#{value.class}): '#{value}'"
          end

          # Recursively re-encode and sanitize potentially bad string values
          event[:attrs] = sanitize_and_reencode_value(event[:attrs])
          event_json = event.to_json
        end

        # generate new request if json size of events in the array exceed maximum request buffer size
        append_event = true
        if total_bytes + event_json.bytesize > @max_request_buffer
          # the case where a single event causes us to exceed the @max_request_buffer
          if events.empty?
            # if we are able to truncate the content inside the @message_field we do so here
            if record.key?(@message_field) &&
              record[@message_field].is_a?(String) &&
              record[@message_field].bytesize > event_json.bytesize - @max_request_buffer

              @log.warn "Received a record that cannot fit within max_request_buffer "\
                "(#{@max_request_buffer}), serialized event size is #{event_json.bytesize}."\
                " The #{@message_field} field will be truncated to fit."
              max_msg_size = @max_request_buffer - event_json.bytesize
              truncated_msg = event[:attrs][@message_field][0...max_msg_size]
              event[:attrs][@message_field] = truncated_msg
              events << event

            # otherwise we drop the event and save ourselves hitting a 4XX response from the server
            else
              @log.warn "Received a record that cannot fit within max_request_buffer "\
                "(#{@max_request_buffer}), serialized event size is #{event_json.bytesize}. "\
                "The #{@message_field} field too short to truncate, dropping event."
            end
            append_event = false
          end

          unless events.empty?
            request = create_request(events, current_threads)
            requests << request
          end

          total_bytes = 0
          current_threads = {}
          events = []
        end

        # if we haven't consumed the current event already
        # add it to the end of our array and keep track of the json bytesize
        if append_event
          events << event
          total_bytes += event_json.bytesize
        end
      }

      # create a final request with any left over events
      unless events.empty?
        request = create_request(events, current_threads)
        requests << request
      end

      requests
    end

    def create_request(events, current_threads)
      # build the scalyr thread objects
      threads = []
      current_threads.each do |tag, id|
        threads << {id:   id.to_s,
                    name: "Fluentd: #{tag}"}
      end

      current_time = to_millis(Fluent::Engine.now)

      body = {token:            @api_write_token,
              client_timestamp: current_time.to_s,
              session:          @session,
              events:           events,
              threads:          threads}

      # add server_attributes hash if it exists
      body[:sessionInfo] = @server_attributes if @server_attributes

      {body: body.to_json, record_count: events.size}
    end
  end
end
