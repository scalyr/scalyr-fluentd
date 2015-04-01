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

class SSLVerifyTest < Scalyr::ScalyrOutTest
  def test_bad_ssl_certificates
    d = create_driver CONFIG + 'ssl_ca_bundle_path /home/invalid'

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )

    logger = flexmock( $log )
    logger.should_receive( :warn ).with( /certificate verification failed/i )
    logger.should_receive( :warn ).with( /certificate verify failed/i )
    logger.should_receive( :warn ).with( /discarding buffer/i )

      d.run
  end
end
