# frozen_string_literal: true

#
# Scalyr Output Plugin for Fluentd
#
# Copyright (C) 2020 Scalyr, Inc.
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

module Scalyr
  def sanitize_and_reencode_value(value)
    # Method which recursively sanitizes the provided value and tries to re-encode all the strings as
    # UTF-8 ignoring any bad unicode sequences
    case value
    when Hash
      return sanitize_and_reencode_hash(value)
    when Array
      return sanitize_and_reencode_array(value)
    when String
      value = sanitize_and_reencode_string(value)
      return value
    end

    # We only need to re-encode strings, for other value types (ints, nils,
    # etc. no reencoding is needed)
    value
  end

  def sanitize_and_reencode_array(array)
    array.each_with_index do |value, index|
      value = sanitize_and_reencode_value(value)
      array[index] = value
    end

    array
  end

  def sanitize_and_reencode_hash(hash)
    hash.each do |key, value|
      hash[key] = sanitize_and_reencode_value(value)
    end

    hash
  end

  def sanitize_and_reencode_string(value)
    # Function which sanitized the provided string value and tries to re-encode it as UTF-8
    # ignoring any encoding error which could arise due to bad or partial unicode sequence
    begin # rubocop:disable Style/RedundantBegin
      value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "<?>").force_encoding("UTF-8") # rubocop:disable Layout/LineLength, Lint/RedundantCopDisableDirective
    rescue # rubocop:disable Style/RescueStandardError
      "failed-to-reencode-as-utf8"
    end
  end
end
