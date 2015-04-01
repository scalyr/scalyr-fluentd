require 'helper'

class SSLVerifyTest < Scalyr::ScalyrOutTest
  def test_bad_ssl_certificates
    d = create_driver CONFIG + 'ssl_ca_bundle_path /home/invalid'

    time = Time.parse("2015-04-01 10:00:00 UTC").to_i
    d.emit( { "a" => 1 }, time )

    exception = assert_raises( OpenSSL::SSL::SSLError, "Invalid certificates should cause request failure" ) {
      d.run
    }
    assert_match /certificate verify failed/i, exception.message
  end
end
