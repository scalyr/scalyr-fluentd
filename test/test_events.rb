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


require 'helper'
require 'fluent/event'

class EventsTest < Scalyr::ScalyrOutTest

  def test_format
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )
    mock.should_receive( :post_request ).with_any_args.and_return( response )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )
    d.expect_format [ "test", time, { "a" => 1 } ].to_msgpack
    d.run
  end

  def test_build_add_events_body_basic_values
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "a" => 1 }
    d.emit( attrs, time )

    attrs["logfile"] = "/fluentd/test";

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        assert( body.key?( "token" ), "Missing token field"  )
        assert( body.key?( "client_timestamp" ), "Missing client_timestamp field" )
        assert( body.key?( "session" ), "Missing session field" )
        assert( !body.key?( "sessionInfo"), "sessionInfo field set, but no sessionInfo" )
        assert( body.key?( "events" ), "missing events field" )
        assert( body.key?( "threads" ), "missing threads field" )
        assert_equal( 1, body['events'].length, "Only expecting 1 event" )
        assert_equal( d.instance.to_nanos( time ), body['events'][0]['ts'].to_i, "Event timestamp differs" )
        assert_equal( attrs, body['events'][0]['attrs'], "Value of attrs differs from log" )
        true
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_dont_override_logfile_field
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "a" => 1 }
    attrs["logfile"] = "/some/log/file";
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with(
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        assert_equal( attrs, body['events'][0]['attrs'], "Value of attrs differs from log" )
        true
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_with_server_attributes
    d = create_driver CONFIG + 'server_attributes { "test":"value" }'

    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "a" => 1 }
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        assert( body.key?( "sessionInfo"), "sessionInfo field set, but no sessionInfo" )
        assert_equal( "value", body["sessionInfo"]["test"] )
        true
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_incrementing_timestamps
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )
    d.emit( { "a" => 2 }, time )

    time = Time.parse("2015-04-01 09:59:00 UTC").to_i
    d.emit( { "a" => 3 }, time )

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        assert_equal( 3, events.length, "Expecting 3 events" )
        #test equal timestamps are increased
        assert events[1]['ts'].to_i > events[0]['ts'].to_i, "Event timestamps must increase"

        #test earlier timestamps are increased
        assert events[2]['ts'].to_i > events[1]['ts'].to_i, "Event timestamps must increase"

        true
      }
      ).and_return( response )

    d.run
  end

  def test_build_add_events_body_thread_ids
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    entries = []

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    entries << [time, { "a" => 1 }]

    es = Fluent::ArrayEventStream.new(entries)
    buffer = d.instance.format_stream("test1", es)

    chunk = d.instance.buffer.new_chunk('')
    chunk << buffer

    buffer = d.instance.format_stream("test2", es)
    chunk << buffer

    mock.should_receive( :post_request ).with( 
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        threads = body['threads']

        assert_equal( 2, threads.length, "Expecting 2 threads, #{threads.length} found" )
        assert_equal( 2, events.length, "Expecting 2 events, #{events.length} found" )
        assert_equal( events[0]['thread'], threads[0]['id'].to_s, "thread id should match event thread id" )
        assert_equal( events[1]['thread'], threads[1]['id'].to_s, "thread id should match event thread id" )
        true
      }
      ).at_least.once.and_return( response )

    d.instance.start
    d.instance.write( chunk )
    d.instance.shutdown
  end

  def test_default_message_field
    d = create_driver CONFIG

    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "log" => "this is a test", "logfile" => "/fluentd/test" }
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with(
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        assert_equal( attrs, body['events'][0]['attrs'], "Value of attrs differs from log" )
        true
      }
      ).and_return( response )

    d.run
  end

  def test_different_message_field
    d = create_driver CONFIG + 'message_field log'

    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "log" => "this is a test" }
    d.emit( attrs, time )

    mock.should_receive( :post_request ).with(
      URI,
      on { |request_body|
        body = JSON.parse( request_body )
        events = body['events']
        assert( events[0]['attrs'].key?( 'message'), "'message' field not found in event" )
        assert_equal( "this is a test", events[0]['attrs']['message'], "'message' field incorrect" )
        assert( !events[0]['attrs'].key?( 'log' ), "'log' field should no longer exist in event" )
        true
      }
      ).and_return( response )

    d.run
  end

  def test_different_message_field_message_already_exists
    d = create_driver CONFIG + 'message_field log'

    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    mock = flexmock( d.instance )
    mock.should_receive( :post_request ).and_return( response )

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    attrs = { "log" => "this is a test", "message" => "uh oh" }
    d.emit( attrs, time )

    logger = flexmock( $log )
    logger.should_receive( :warn ).with( /overwriting log record field 'message'/i ).at_least().once()

    d.run
  end

end

