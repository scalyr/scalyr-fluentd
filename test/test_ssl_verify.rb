# frozen_string_literal: true

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

require "helper"
require "flexmock/test_unit"

class SSLVerifyTest < Scalyr::ScalyrOutTest
  def test_good_ssl_certificates
    d = create_driver CONFIG

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, {"a" => 1})

      logger = flexmock($log)
      logger.should_receive(:warn).times(0).with(/certificate verification failed/i)
      logger.should_receive(:warn).times(0).with(/certificate verify failed/i)
      logger.should_receive(:warn).once.with(/discarding buffer/i)
    end
  end

  def test_no_ssl_certificates
    d = create_driver %(
      api_write_token test_token
    )

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, {"a" => 1})

      logger = flexmock($log)
      logger.should_receive(:warn).times(0).with(/certificate verification failed/i)
      logger.should_receive(:warn).times(0).with(/certificate verify failed/i)
      logger.should_receive(:warn).once.with(/discarding buffer/i)
    end
  end

  def test_bad_ssl_certificates
    d = create_driver CONFIG + "ssl_ca_bundle_path /home/invalid"

    d.run(default_tag: "test") do
      time = event_time("2015-04-01 10:00:00 UTC")
      d.feed(time, {"a" => 1})

      logger = flexmock($log)
      logger.should_receive(:warn).once.with(/certificate verification failed/i)
      logger.should_receive(:warn).once.with(/certificate verify failed/i)
      logger.should_receive(:warn).once.with(/discarding buffer/i)
    end
  end

  def test_bad_system_ssl_certificates
    `sudo mv #{OpenSSL::X509::DEFAULT_CERT_FILE} /tmp/system_certs`

    begin
      d = create_driver %(
        api_write_token test_token
      )

      d.run(default_tag: "test") do
        time = event_time("2015-04-01 10:00:00 UTC")
        d.feed(time, {"a" => 1})

        logger = flexmock($log)
        logger.should_receive(:warn).once.with(/certificate verification failed/i)
        logger.should_receive(:warn).once.with(/certificate verify failed/i)
        logger.should_receive(:warn).once.with(/discarding buffer/i)
      end
    ensure
      `sudo mv /tmp/system_certs #{OpenSSL::X509::DEFAULT_CERT_FILE}`
    end
  end

  def test_hostname_verification
    agent_scalyr_com_ip = `dig +short agent.scalyr.com 2> /dev/null | tail -n 1 | tr -d "\n"`
    if agent_scalyr_com_ip.empty?
      agent_scalyr_com_ip = `getent hosts agent.scalyr.com \
      | awk '{ print $1 }' | tail -n 1 | tr -d "\n"`
    end
    mock_host = "invalid.mitm.should.fail.test.agent.scalyr.com"
    etc_hosts_entry = "#{agent_scalyr_com_ip} #{mock_host}"
    hosts_bkp = `sudo cat /etc/hosts`
    hosts_bkp = hosts_bkp.chomp
    # Add mock /etc/hosts entry and config scalyr_server entry
    `echo "#{etc_hosts_entry}" | sudo tee -a /etc/hosts`

    begin
      d = create_driver %(
        api_write_token test_token
        scalyr_server https://invalid.mitm.should.fail.test.agent.scalyr.com:443
      )

      d.run(default_tag: "test") do
        time = event_time("2015-04-01 10:00:00 UTC")
        d.feed(time, {"a" => 1})

        logger = flexmock($log)
        logger.should_receive(:warn).once.with(/certificate verification failed/i)
        logger.should_receive(:warn).once.with(/certificate verify failed/i)
        logger.should_receive(:warn).once.with(/discarding buffer/i)
      end
    ensure
      # Clean up the hosts file
      `sudo truncate -s 0 /etc/hosts`
      `echo "#{hosts_bkp}" | sudo tee -a /etc/hosts`
    end
  end
end
