require 'fluent/test'
require 'fluent/plugin/out_scalyr'

module Scalyr
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
  end
end
