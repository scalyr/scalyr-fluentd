require 'flexmock/test_unit'
require 'fluent/test'
require 'fluent/plugin/out_scalyr'

class ScalyrOutTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    api_write_token test_token
  ]

  def create_driver( conf = CONFIG )
    Fluent::Test::BufferedOutputTestDriver.new( Scalyr::ScalyrOut ).configure( conf )
  end

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

  def test_handle_response_missing_status
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "message":"An invalid message" }'  )
    exception = assert_raise( Scalyr::ServerError, "Server error not raised for missing status" ) {
      d.instance.handle_response( response )
    }

    assert_equal( "JSON response does not contain status message", exception.message )
  end

  def test_handle_response_discard_buffer
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "message":"An invalid message", "status":"error/server/discardBuffer" }'  )
    logger = flexmock( $log )
    logger.should_receive( :warn ).with( /buffer dropped/i )
    assert_nothing_raised( Scalyr::ServerError, Scalyr::ClientError, "Nothing should be raised when discarding the buffer" ) {
      d.instance.handle_response( response )
    }

  end

  def test_handle_response_unknown_error
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "message":"An invalid message", "status":"error/other" }'  )
    exception = assert_raise( Scalyr::ServerError, "Server error not raised for error status" ) {
      d.instance.handle_response( response )
    }
    assert_equal( "error/other", exception.message )
  end

  def test_handle_response_client_error
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "message":"An invalid message", "status":"error/client/test" }'  )
    exception = assert_raise( Scalyr::ClientError, "Client  error not raised for error status" ) {
      d.instance.handle_response( response )
    }
    assert_equal( "error/client/test", exception.message )
  end

  def test_handle_response_server_error
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "message":"An invalid message", "status":"error/server/test" }'  )
    exception = assert_raise( Scalyr::ServerError, "Server error not raised for error status" ) {
      d.instance.handle_response( response )
    }
    assert_equal( "error/server/test", exception.message )
  end

  def test_handle_response_code_not_200
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '404', :body =>'{ "status":"error/server/fileNotFound" }'  )
    exception = assert_raise( Scalyr::ServerError, Scalyr::ClientError, "Error raised on success" ) {
      d.instance.handle_response( response )
    }
    assert_equal( "error/server/fileNotFound", exception.message )
  end

  def test_handle_response_code_200
    d = create_driver
    response = flexmock( Net::HTTPResponse, :code => '200', :body =>'{ "status":"success" }'  )
    exception = assert_nothing_raised( Scalyr::ServerError, Scalyr::ClientError, "Error raised on success" ) {
      d.instance.handle_response( response )
    }
  end

end

