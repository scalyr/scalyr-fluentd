require 'helper'
require 'flexmock/test_unit'

class HandleResponseTest < Scalyr::ScalyrOutTest

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

