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

require "fluent/plugin/scalyr_utils"
include Scalyr # rubocop:disable Style/MixinUsage

module Scalyr
  class UtilsTest < Test::Unit::TestCase
    def test_sanitize_and_reencode_value_simple_types
      # Simple value - string
      result = sanitize_and_reencode_value("test foo")
      assert_equal("test foo", result)

      # Simple value - string with bad unicode sequences
      result = sanitize_and_reencode_value("test \xC2 foo \xC2 bar")
      assert_equal("test <?> foo <?> bar", result)

      # Simple value - int
      result = sanitize_and_reencode_value(100)
      assert_equal(100, result)

      # Simple value - nill
      result = sanitize_and_reencode_value(nil)
      assert_equal(nil, result)

      # Simple value - bool
      result = sanitize_and_reencode_value(true)
      assert_equal(true, result)

      result = sanitize_and_reencode_value(false)
      assert_equal(false, result)
    end

    def test_sanitize_and_reencode_value_complex_nested_types
      actual = [1, 2, "a", "b", nil, "7", "\xC2"]
      expected = [1, 2, "a", "b", nil, "7", "<?>"]

      result = sanitize_and_reencode_value(actual)
      assert_equal(expected, result)

      actual = [1, 2, "a", "b", nil, "7",
                [8, 9, [10, "\xC2"]],
                {"a" => 1, "b" => "\xC2"}]
      expected = [1, 2, "a", "b", nil, "7",
                  [8, 9, [10, "<?>"]],
                  {"a" => 1, "b" => "<?>"}]

      result = sanitize_and_reencode_value(actual)
      assert_equal(expected, result)

      actual = {
        "a" => "1",
        "b" => {
          "c" => "\xC2",
          "d" => "e",
          "f" => nil,
          "g" => {
            "h" => "bar \xC2",
            "b" => 3,
            "l" => [1, 2, "foo\xC2", 3, 4, 5]
          }
        }
      }
      expected = {
        "a" => "1",
        "b" => {
          "c" => "<?>",
          "d" => "e",
          "f" => nil,
          "g" => {
            "h" => "bar <?>",
            "b" => 3,
            "l" => [1, 2, "foo<?>", 3, 4, 5]
          }
        }
      }
      result = sanitize_and_reencode_value(actual)
      assert_equal(expected, result)
    end
  end
end
