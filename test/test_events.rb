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

require "helper"
require "flexmock/test_unit"
require "fluent/event"

class EventsTest < Scalyr::ScalyrOutTest
  def test_format
    d = create_driver

    time = event_time("2015-04-01 10:00:00 UTC")

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)
    mock.should_receive(:post_request).with_any_args.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, {"a" => 1})
    end

    expected = [
      ["test", time.sec, time.nsec, {"a" => 1}].to_msgpack
    ]

    assert_equal(expected, d.formatted)
  end

  def test_build_add_events_body_basic_values
    d = create_driver

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"a" => 1}
    attrs["logfile"] = "/fluentd/test"

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        assert(body.key?("token"), "Missing token field")
        assert(body.key?("client_timestamp"), "Missing client_timestamp field")
        assert(body.key?("sessionInfo"), "sessionInfo field set, but no sessionInfo")
        assert(body.key?("events"), "missing events field")
        assert(body.key?("threads"), "missing threads field")
        assert_equal(1, body["events"].length, "Only expecting 1 event")
        assert_equal(time.sec * 1_000_000_000, body["events"][0]["ts"].to_i,
                     "Event timestamp differs")
        assert_equal(attrs, body["events"][0]["attrs"], "Value of attrs differs from log")
        mock_called = true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_build_add_events_body_dont_override_logfile_field
    d = create_driver

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"a" => 1}
    attrs["logfile"] = "/some/log/file"

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        assert_equal(attrs, body["events"][0]["attrs"], "Value of attrs differs from log")
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_build_add_events_body_with_server_attributes
    d = create_driver CONFIG + 'server_attributes { "test":"value" }'

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"a" => 1}

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        assert(body.key?("sessionInfo"), "sessionInfo field set, but no sessionInfo")
        assert_equal("value", body["sessionInfo"]["test"])
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_build_add_events_body_incrementing_timestamps
    d = create_driver

    time1 = event_time("2015-04-01 10:00:00 UTC")
    time2 = event_time("2015-04-01 09:59:00 UTC")

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        events = body["events"]
        assert_equal(3, events.length, "Expecting 3 events")
        # Since 0.8.10 timestamps dont need to increase anymore
        assert events[1]["ts"].to_i == events[0]["ts"].to_i, "Event timestamps must be the same"
        assert events[2]["ts"].to_i < events[0]["ts"].to_i, "Event timestamps must be less"
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time1, {"a" => 1})
      d.feed(time1, {"a" => 2})
      d.feed(time2, {"a" => 3})
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_build_add_events_body_non_json_serializable_value
    d = create_driver

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"a" => 1}
    attrs["int1"] = 1_601_923_119
    attrs["int2"] = Integer(1_601_923_119)
    attrs["int3"] = Integer(9_223_372_036_854_775_807)
    attrs["int4"] = Integer(-1)
    attrs["nil"] = nil
    attrs["array"] = [1, 2, "a", "b", nil]
    attrs["hash"] = {
      "a" => "1",
      "b" => "c"
    }
    attrs["logfile"] = "/some/log/file"

    # This partial unicode sequence will fail encoding so we make sure it doesn't break the plugin
    # and we correctly cast it to a value which we can send to the API
    attrs["partial_unicode_sequence"] = "\xC2"
    attrs["array_with_partial_unicode_sequence"] = [1, 2, "a", "b", nil, "7", "\xC2"]
    attrs["nested_array_with_partial_unicode_sequence"] = [1, 2, "a", "b", nil, "7",
                                                           [8, 9, [10, "\xC2"]],
                                                           {"a" => 1, "b" => "\xC2"}]
    attrs["hash_with_partial_unicode_sequence"] = {
      "a" => "1",
      "b" => "\xC2",
      "c" => nil
    }
    attrs["nested_hash_with_partial_unicode_sequence"] = {
      "a" => "1",
      "b" => {
        "c" => "\xC2",
        "d" => "e",
        "f" => nil,
        "g" => {
          "h" => "\xC2",
          "b" => 3
        }
      }
    }

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    expected_attrs = attrs.clone
    expected_attrs["partial_unicode_sequence"] = "<?>"
    expected_attrs["array_with_partial_unicode_sequence"][-1] = "<?>"
    expected_attrs["nested_array_with_partial_unicode_sequence"][-2][-1][-1] = "<?>"
    expected_attrs["nested_array_with_partial_unicode_sequence"][-1]["b"] = "<?>"
    expected_attrs["hash_with_partial_unicode_sequence"]["b"] = "<?>"
    expected_attrs["nested_hash_with_partial_unicode_sequence"]["b"]["c"] = "<?>"
    expected_attrs["nested_hash_with_partial_unicode_sequence"]["b"]["g"]["h"] = "<?>"

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        assert_equal(expected_attrs, body["events"][0]["attrs"], "Value of attrs differs from log")
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_default_message_field
    d = create_driver CONFIG

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"log" => "this is a test", "logfile" => "/fluentd/test"}

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        assert_equal(attrs, body["events"][0]["attrs"], "Value of attrs differs from log")
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_different_message_field
    d = create_driver CONFIG + "message_field log"

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"log" => "this is a test"}

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock_called = false

    mock.should_receive(:post_request).with(
      URI,
      on {|request_body|
        body = JSON.parse(request_body)
        events = body["events"]
        assert(events[0]["attrs"].key?("message"), "'message' field not found in event")
        assert_equal("this is a test", events[0]["attrs"]["message"], "'message' field incorrect")
        assert(!events[0]["attrs"].key?("log"), "'log' field should no longer exist in event")
        mock_called = true
        true
      }
    ).once.and_return(response)

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end

    assert_equal(mock_called, true, "mock method was never called!")
  end

  def test_different_message_field_message_already_exists
    d = create_driver CONFIG + "message_field log"

    time = event_time("2015-04-01 10:00:00 UTC")
    attrs = {"log" => "this is a test", "message" => "uh oh"}

    response = flexmock(Net::HTTPResponse, code: "200", body: '{ "status":"success" }')
    mock = flexmock(d.instance)

    mock.should_receive(:post_request).once.and_return(response)

    logger = flexmock($log)
    logger.should_receive(:warn).with(/overwriting log record field 'message'/i).at_least.once

    d.run(default_tag: "test") do
      d.feed(time, attrs)
    end
  end
end
