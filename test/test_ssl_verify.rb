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
require 'flexmock/test_unit'

class SSLVerifyTest < Scalyr::ScalyrOutTest
  def test_good_ssl_certificates
    d = create_driver CONFIG

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, { "a" => 1 })

      logger = flexmock( $log )
      logger.should_receive( :warn ).times(0).with( /certificate verify failed/i )
      logger.should_receive( :warn ).once().with( /discarding buffer/i )
    end
  end

  def test_no_ssl_certificates
    d = create_driver %[
      api_write_token test_token
    ]

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, { "a" => 1 })

      logger = flexmock( $log )
      logger.should_receive( :warn ).times(0).with( /certificate verify failed/i )
      logger.should_receive( :warn ).once().with( /discarding buffer/i )
    end
  end

  def test_bad_ssl_certificates
    d = create_driver CONFIG + 'ssl_ca_bundle_path /home/invalid'

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, { "a" => 1 })

      logger = flexmock( $log )
      logger.should_receive( :warn ).once().with( /certificate verify failed/i )
    end
  end
end
