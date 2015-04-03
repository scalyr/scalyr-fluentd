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


require 'fluent/plugin/scalyr-exceptions'
require 'json'
require 'net/http'
require 'net/https'
require 'securerandom'
require 'thread'

module Scalyr
  class ScalyrOut < Fluent::BufferedOutput
    Fluent::Plugin.register_output( 'scalyr', self )

    config_param :api_write_token, :string
    config_param :session_info, :hash, :default => nil
    config_param :scalyr_server, :string, :default => "https://agent.scalyr.com/"
    config_param :ssl_ca_bundle_path, :string, :default => "/etc/ssl/certs/ca-bundle.crt"
    config_param :ssl_verify_peer, :bool, :default => true
    config_param :ssl_verify_depth, :integer, :default => 5

    config_set_default :retry_limit, 40 #try a maximum of 40 times before discarding
    config_set_default :retry_wait, 5 #wait a minimum of 5 seconds before retrying again
    config_set_default :max_retry_wait,  30 #wait a maximum of 30 seconds per retry
    config_set_default :flush_interval, 5 #default flush interval of 5 seconds

    def configure( conf )
      #need to call this before super because there doesn't seem to be any other way to
      #set the default value for the buffer_chunk_limit, which is created and configured in super
      if !conf.key? "buffer_chunk_limit"
        conf["buffer_chunk_limit"] = "100k"
      end
      if !conf.key? "buffer_queue_limit"
        conf["buffer_queue_limit"] = 1024
      end
      super

      if @buffer.buffer_chunk_limit > 1024*1024
        $log.warn "Buffer chunk size is greater than 1Mb.  This may result in requests being rejected by Scalyr"
      end

      @scalyr_server << '/' unless @scalyr_server.end_with?('/')

      @add_events_uri = URI @scalyr_server + "addEvents"
    end

    def start
      super
      #Generate a session id.  This will be called once for each <match> in fluent.conf that uses scalyr
      @session = SecureRandom.uuid

      @sync = Mutex.new
      #the following variables are all under the control of the above mutex
        @thread_ids = Hash.new #hash of tags -> id
        @next_id = 1 #incrementing thread id for the session
        @last_timestamp = 0 #timestamp of most recent event

    end

    def format( tag, time, record )
      [tag, time, record].to_msgpack
    end

    #called by fluentd when a chunk of log messages is ready
    def write( chunk )
      begin
        body = self.build_add_events_body( chunk )
        response = self.post_request( @add_events_uri, body )
        self.handle_response( response )
      rescue OpenSSL::SSL::SSLError => e
        if e.message.include? "certificate verify failed"
          $log.warn "SSL certificate verification failed.  Please make sure your certificate bundle is configured correctly and points to a valid file. You can configure this with the ssl_ca_bundle_path configuration option. The current value of ssl_ca_bundle_path is '#{@ssl_ca_bundle_path}'"
        end
        $log.warn e.message
        $log.warn "Discarding buffer chunk without retrying or logging to <secondary>"
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

      response_hash = JSON.parse( response.body )

      #make sure the JSON reponse has a "status" field
      if !response_hash.key? "status"
        $log.debug "JSON response does not contain status message"
        raise Scalyr::ServerError.new "JSON response does not contain status message"
      end

      status = response_hash["status"]

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

    def build_add_events_body( chunk )

      #set of unique scalyr threads for this chunk
      current_threads = Hash.new

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
        events << { :thread => thread_id.to_s,
                    :ts => timestamp.to_s,
                    :attrs => record
                  }

      }

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

      #add session_info hash if it exists
      if @session_info
        body[:sessionInfo] = @session_info
      end

      body.to_json
    end

  end
end
