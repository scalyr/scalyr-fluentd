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


require 'fluent/plugin/scalyr-session'
require 'test/unit'
require 'thread'

class SessionTest < Test::Unit::TestCase

  def test_single_session
    session1 = Scalyr::Session.instance.session
    session2 = Scalyr::Session.instance.session

    assert_equal session1, session2, "Session IDs should be equal"
  end

  def test_last_timestamp_equal
    session = Scalyr::Session.instance

    timestamp1, id = session.get_timestamp_and_id( 10, "test" )
    timestamp2, id = session.get_timestamp_and_id( 10, "test" )

    assert( timestamp2 > timestamp1, "Timestamps should be strictly increasing for the session" )
  end

  def test_last_timestamp_less_than
    session = Scalyr::Session.instance

    timestamp1, id = session.get_timestamp_and_id( 10, "test" )
    timestamp2, id = session.get_timestamp_and_id( 8, "test" )

    assert( timestamp2 > timestamp1, "Timestamps should be strictly increasing for the session" )
  end

  def test_thread_id_equal
    session = Scalyr::Session.instance
    timestamp, id1 = session.get_timestamp_and_id( 10, "test" )
    timestamp, id2 = session.get_timestamp_and_id( 10, "test" )

    assert_equal( id1, id2, "ids for identical tags should be identical" )
  end

  def test_thread_id_different
    session = Scalyr::Session.instance
    timestamp, id1 = session.get_timestamp_and_id( 10, "test1" )
    timestamp, id2 = session.get_timestamp_and_id( 10, "test2" )

    assert_not_equal( id1, id2, "ids for differet tags should be different" )
  end

end


