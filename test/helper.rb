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


require 'fluent/test'
require 'fluent/plugin/out_scalyr'

module Scalyr
  class ScalyrOutTest < Test::Unit::TestCase
    def setup
      Fluent::Test.setup
    end

    CONFIG = %[
      api_write_token test_token
      ssl_ca_bundle_path /etc/ssl/certs/ca-certificates.crt
    ]

    def create_driver( conf = CONFIG )
      Fluent::Test::BufferedOutputTestDriver.new( Scalyr::ScalyrOut ).configure( conf )
    end
  end
end
