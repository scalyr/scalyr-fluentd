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


require 'fluent/plugin/output'
require 'fluent/plugin/scalyr-exceptions'
require 'fluent/plugin_helper/compat_parameters'
require 'json'
require 'net/http'
require 'net/https'
require 'securerandom'
require 'thread'

module Scalyr
  class ScalyrOut < Fluent::Plugin::Output
    Fluent::Plugin.register_output( 'scalyr', self )
    helpers :compat_parameters

    config_param :api_write_token, :string
    config_param :server_attributes, :hash, :default => nil
    config_param :scalyr_server, :string, :default => "https://agent.scalyr.com/"
    config_param :ssl_ca_bundle_path, :string, :default => "/etc/ssl/certs/ca-bundle.crt"
    config_param :ssl_verify_peer, :bool, :default => true
    config_param :ssl_verify_depth, :integer, :default => 5
    config_param :message_field, :string, :default => "message"
    config_param :max_request_buffer, :integer, :default => 1024*1024
    config_param :force_message_encoding, :string, :default => nil
    config_param :replace_invalid_utf8, :bool, :default => false

    config_section :buffer do
      config_set_default :retry_max_times, 40 #try a maximum of 40 times before discarding
      config_set_default :retry_max_interval,  30 #wait a maximum of 30 seconds per retry
      config_set_default :retry_wait, 5 #wait a minimum of 5 seconds per retry
      config_set_default :flush_interval, 5 #default flush interval of 5 seconds
      config_set_default :chunk_limit_size, 1024*100 #default chunk size of 100k
      config_set_default :queue_limit_length, 1024 #default queue size of 1024
    end

    # support for version 0.14.0:
    def compat_parameters_default_chunk_key
      ""
    end

    def formatted_to_msgpack_binary
      true
    end

    def configure( conf )

      if conf.elements('buffer').empty?
        $log.warn "Pre 0.14.0 configuration file detected.  Please consider updating your configuration file"
      end

      compat_parameters_buffer( conf, default_chunk_key: '' )

      super

      if @buffer.chunk_limit_size > 1024*1024
        $log.warn "Buffer chunk size is greater than 1Mb.  This may result in requests being rejected by Scalyr"
      end

      if @max_request_buffer > (1024*1024*3)
        $log.warn "Maximum request buffer > 3Mb.  This may result in requests being rejected by Scalyr"
      end

      @message_encoding = nil
      if @force_message_encoding.to_s != ''
        begin
          @message_encoding = Encoding.find( @force_message_encoding )
          $log.debug "Forcing message encoding to '#{@force_message_encoding}'"
        rescue ArgumentError
          $log.warn "No encoding '#{@force_message_encoding}' found.  Ignoring"
        end
      end

      @scalyr_server << '/' unless @scalyr_server.end_with?('/')

      @add_events_uri = URI @scalyr_server + "addEvents"

      num_threads = @buffer_config.flush_thread_count

      #forcibly limit the number of threads to 1 for now, to ensure requests always have incrementing timestamps
      raise Fluent::ConfigError, "num_threads is currently limited to 1. You specified #{num_threads}." if num_threads > 1
    end

    def start
      super
      $log.info "Scalyr Fluentd Plugin ID - #{self.plugin_id()}"
      #Generate a session id.  This will be called once for each <match> in fluent.conf that uses scalyr
      @session = SecureRandom.uuid

      @sync = Mutex.new
      #the following variables are all under the control of the above mutex
        @thread_ids = Hash.new #hash of tags -> id
        @next_id = 1 #incrementing thread id for the session
        @last_timestamp = 0 #timestamp of most recent event

    end

    def format( tag, time, record )
      begin
        if @message_field != "message"
          if record.key? @message_field
            if record.key? "message"
              $log.warn "Overwriting log record field 'message'.  You are seeing this warning because in your fluentd config file you have configured the '#{@message_field}' field to be converted to the 'message' field, but the log record already contains a field called 'message' and this is now being overwritten."
            end
            record["message"] = record[@message_field]
            record.delete( @message_field )
          end
        end

        if @message_encoding
          if @replace_invalid_utf8 and @message_encoding == Encoding::UTF_8
            record["message"] = record["message"].encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => "<?>").force_encoding('UTF-8')
          else
            record["message"].force_encoding( @message_encoding )
          end
        end
        [tag, time, record].to_msgpack

      rescue JSON::GeneratorError
        $log.warn "Unable to format message due to JSON::GeneratorError.  Record is:\n\t#{record.to_s}"
        raise
      end
    end

    #called by fluentd when a chunk of log messages is ready
    def write( chunk )
      begin
        $log.debug "Size of chunk is: #{chunk.size}"
        requests = self.build_add_events_body( chunk )
        $log.debug "Chunk split into #{requests.size} request(s)."

        requests.each_with_index { |request, index|
          $log.debug "Request #{index + 1}/#{requests.size}: #{request[:body].bytesize} bytes"
          begin
            response = self.post_request( @add_events_uri, request[:body] )
            self.handle_response( response )
          rescue OpenSSL::SSL::SSLError => e
            if e.message.include? "certificate verify failed"
              $log.warn "SSL certificate verification failed.  Please make sure your certificate bundle is configured correctly and points to a valid file. You can configure this with the ssl_ca_bundle_path configuration option. The current value of ssl_ca_bundle_path is '#{@ssl_ca_bundle_path}'"
            end
            $log.warn e.message
            $log.warn "Discarding buffer chunk without retrying or logging to <secondary>"
          rescue Scalyr::Client4xxError => e
            $log.warn "4XX status code received for request #{index + 1}/#{requests.size}.  Discarding buffer without retrying or logging.\n\t#{response.code} - #{e.message}\n\tChunk Size: #{chunk.size}\n\tLog messages this request: #{request[:record_count]}\n\tJSON payload size: #{request[:body].bytesize}\n\tSample: #{request[:body][0,1024]}..."

          end
        }

      rescue JSON::GeneratorError
        $log.warn "Unable to format message due to JSON::GeneratorError."
        raise
      end
    end



    #explicit function to convert to nanoseconds
    #will make things easier to maintain if/when fluentd supports higher than second resolutions
    def to_nanos( seconds )
      seconds * 10**9
    end

    #explicit function to convert to milliseconds
    #will make things easier to maintain if/when fluentd supports higher than second resolutions
    def to_millis( seconds )
      seconds * 10**6
    end

    def post_request( uri, body )

      https = Net::HTTP.new( uri.host, uri.port )
      https.use_ssl = true

      #verify peers to prevent potential MITM attacks
      if @ssl_verify_peer
        https.ca_file = @ssl_ca_bundle_path
        https.verify_mode = OpenSSL::SSL::VERIFY_PEER
        https.verify_depth = @ssl_verify_depth
      end

      post = Net::HTTP::Post.new uri.path
      post.add_field( 'Content-Type', 'application/json' )

      post.body = body

      https.request( post )

    end

    def handle_response( response )
      $log.debug "Response Code: #{response.code}"
      $log.debug "Response Body: #{response.body}"

      response_hash = Hash.new

      begin
        response_hash = JSON.parse( response.body )
      rescue
        response_hash["status"] = "Invalid JSON response from server"
      end

      #make sure the JSON reponse has a "status" field
      if !response_hash.key? "status"
        $log.debug "JSON response does not contain status message"
        raise Scalyr::ServerError.new "JSON response does not contain status message"
      end

      status = response_hash["status"]

      #4xx codes are handled separately
      if response.code =~ /^4\d\d/
        raise Scalyr::Client4xxError.new status
      else
        if status != "success"
          if status =~ /discardBuffer/
            $log.warn "Received 'discardBuffer' message from server.  Buffer dropped."
          elsif status =~ %r"/client/"i
            raise Scalyr::ClientError.new status
          else #don't check specifically for server, we assume all non-client errors are server errors
            raise Scalyr::ServerError.new status
          end
        elsif !response.code.include? "200" #response code is a string not an int
          raise Scalyr::ServerError
        end
      end

    end

    def build_add_events_body( chunk )

      #requests
      requests = Array.new

      #set of unique scalyr threads for this chunk
      current_threads = Hash.new

      #byte count
      total_bytes = 0

      #create a Scalyr event object for each record in the chunk
      events = Array.new
      chunk.msgpack_each {|(tag,time,record)|

        timestamp = self.to_nanos( time )
        thread_id = 0

        @sync.synchronize {
          #ensure timestamp is at least 1 nanosecond greater than the last one
          timestamp = [timestamp, @last_timestamp + 1].max
          @last_timestamp = timestamp

          #get thread id or add a new one if we haven't seen this tag before
          if @thread_ids.key? tag
            thread_id = @thread_ids[tag]
          else
            thread_id = @next_id
            @thread_ids[tag] = thread_id
            @next_id += 1
          end
        }

        #then update the map of threads for this chunk
        current_threads[tag] = thread_id

        #add a logfile field if one doesn't exist
        if !record.key? "logfile"
          record["logfile"] = "/fluentd/#{tag}"
        end

        #append to list of events
        event = { :thread => thread_id.to_s,
                  :ts => timestamp.to_s,
                  :attrs => record
                }

        #get json string of event to keep track of how many bytes we are sending

        begin
          event_json = event.to_json
        rescue JSON::GeneratorError, Encoding::UndefinedConversionError => e
          $log.warn "#{e.class}: #{e.message}"

	  # Send the faulty event to a label @ERROR block and allow to handle it there (output to exceptions file for ex)
	  router.emit_error_event(tag, time, record, e)

          event[:attrs].each do |key, value|
            $log.debug "\t#{key} (#{value.encoding.name}): '#{value}'"
            event[:attrs][key] = value.encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => "<?>").force_encoding('UTF-8')
          end
          event_json = event.to_json
        end

        #generate new request if json size of events in the array exceed maximum request buffer size
        append_event = true
        if total_bytes + event_json.bytesize > @max_request_buffer
          #make sure we always have at least one event
          if events.size == 0
            events << event
            append_event = false
          end
          request = self.create_request( events, current_threads )
          requests << request

          total_bytes = 0
          current_threads = Hash.new
          events = Array.new
        end

        #if we haven't consumed the current event already
        #add it to the end of our array and keep track of the json bytesize
        if append_event
          events << event
          total_bytes += event_json.bytesize
        end

      }

      #create a final request with any left over events
      request = self.create_request( events, current_threads )
      requests << request

    end

    def create_request( events, current_threads )
      #build the scalyr thread objects
      threads = Array.new
      current_threads.each do |tag, id|
        threads << { :id => id.to_s,
                     :name => "Fluentd: #{tag}"
                   }
      end

      current_time = self.to_millis( Fluent::Engine.now )

      body = { :token => @api_write_token,
                  :client_timestamp => current_time.to_s,
                  :session => @session,
                  :events => events,
                  :threads => threads
                }

      #add server_attributes hash if it exists
      if @server_attributes
        body[:sessionInfo] = @server_attributes
      end

      { :body => body.to_json, :record_count => events.size }
    end

  end
end
