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

class ConfigTest  < Scalyr::ScalyrOutTest

  def test_default_params
    d = create_driver
    assert_nil( d.instance.session_info, "Default sessionInfo not nil" )
    assert( d.instance.ssl_verify_peer, "Default ssl_verify_peer should be true" )

    #check default buffer limits because they are set outside of the config_set_default
    assert_equal( 100*1024, d.instance.buffer.buffer_chunk_limit, "Buffer chunk limit should be 100k" )
    assert_equal( 1024, d.instance.buffer.buffer_queue_limit, "Buffer queue limit should be 1024" )
  end

  def test_configure_ssl_verify_peer
    d = create_driver CONFIG + 'ssl_verify_peer false'
    assert( !d.instance.ssl_verify_peer, "Config failed to set ssl_verify_peer" )
  end

  def test_scalyr_server_adding_trailing_slash
    d = create_driver CONFIG + 'scalyr_server http://www.example.com'
    assert_equal( "http://www.example.com/", d.instance.scalyr_server, "Missing trailing slash for scalyr_server" )
  end

  def test_configure_ssl_ca_bundle_path
    d = create_driver CONFIG + 'ssl_ca_bundle_path /test/ca-bundle.crt'
    assert_equal( "/test/ca-bundle.crt", d.instance.ssl_ca_bundle_path, "Config failed to set ssl_ca_bundle_path" )
  end

  def test_configure_ssl_verify_depth
    d = create_driver CONFIG + 'ssl_verify_depth 10'
    assert_equal( 10, d.instance.ssl_verify_depth, "Config failed to set ssl_verify_depth" )
  end

  def test_configure_session_info
    d = create_driver CONFIG + 'session_info { "test":"value" }'
    assert_equal( "value", d.instance.session_info["test"], "Config failed to set session info" )
  end
end

