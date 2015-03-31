
require 'fluent/plugin/scalyr-exceptions'
require 'json'
require 'net/http'
require 'net/https'
require 'securerandom'
require 'thread'

module Scalyr
  class FluentLogger < Fluent::BufferedOutput
    Fluent::Plugin.register_output( 'scalyr', self )

    config_param :api_write_token, :string
    config_param :session_info, :hash, :default => nil
    config_param :add_events, :string, :default => "https://www.scalyr.com/addEvents"
    config_param :ssl_ca_bundle_path, :string, :default => "/etc/ssl/certs/ca-bundle.crt"
    config_param :ssl_verify_peer, :bool, :default => true
    config_param :ssl_verify_depth, :integer, :default => 5

    config_set_default :retry_limit, 5 #try a maximum of 5 times before discarding
    config_set_default :retry_wait, 5 #wait a minimum of 5 seconds before retrying again
    config_set_default :max_retry_wait,  30 #wait a maximum of 30 seconds per retry
    config_set_default :flush_interval, 5 #default flush interval of 5 seconds

    def configure( conf )
      #need to call this before super because there doesn't seem to be any other way to
      #set the default value for the buffer_chunk_limit, which is created and configured in super
      if !conf.key? "buffer_chunk_limit"
        conf["buffer_chunk_limit"] = "256k"
      end
      super

      if @buffer.buffer_chunk_limit > 1024*1024
        $log.warn "Buffer chunk size is greater than 1Mb.  This may result in requests being rejected by Scalyr"
      end

      @add_events_uri = URI @add_events
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
      body = self.build_add_events_body( chunk )
      response = self.post_request( @add_events_uri, body )
      self.handle_response( response )
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
        raise Scalyr::ServerError
      end

      status = response_hash["status"]

      if status.start_with? "error"
        if status =~ %r"/client/"i
          raise Scalyr::ClientError
        else #don't check specifically for server, we assume all non-client errors are server errors
          raise Scalyr::ServerError
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


        #append to list of events
        events << { :thread => thread_id.to_s,
                    :ts => timestamp.to_s,
                    :attrs => record
                  }

      }

      #build the scalyr thread objects
      threads = Array.new
      current_threads.each do |tag, id|
        threads << { :id => id,
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
