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

require 'securerandom'
require 'thread'

module Scalyr
  class Session
    include Singleton
    
    def initialize
      #Generate a session id.
      @session = SecureRandom.uuid

      @sync = Mutex.new
      #the following variables are all under the control of the above mutex
        @thread_ids = Hash.new #hash of tags -> id
        @next_id = 1 #incrementing thread id for the session
        @last_timestamp = 0 #timestamp of most recent event
    end

    # Get a strictly increasing timestamp for the session, and also the 
    # thread_id currently in use for this session based on the tag.
    # This is a single function so that callers don't have to block
    # on the mutex multiple times when calling this in a loop
    def get_timestamp_and_id( timestamp, tag )
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

      return timestamp, thread_id
    end

    #don't protect reader access to session as creation is already thread safe,
    #and once created the value will never change
    attr_reader :session
private
    #these should not be accessed outside of the class
    attr_accessor :sync, :thread_ids, :next_id, :last_timestamp
    attr_writer :session
  
  end
end
