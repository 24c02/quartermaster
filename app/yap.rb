require 'slack-notifier'

module Quartermaster
  class MockNotifier
    def initialize(tag)
      @tag = tag
    end
    def ping(message)
      puts "[#{@tag}]: #{message}"
    end
  end
  class Yap
    if ENV["ENV"] == "PROD"
      @ops = Slack::Notifier.new ENV["OPS_WEBHOOK"]
      @noise = Slack::Notifier.new ENV["NOISE_WEBHOOK"]
    else
      @ops = MockNotifier.new "OPS"
      @noise = MockNotifier.new "NOISE"
    end

    def self.post_to_ops(message)
      @ops.ping message
    end

    def self.post_to_noise(message)
      @noise.ping message
    end
  end
end