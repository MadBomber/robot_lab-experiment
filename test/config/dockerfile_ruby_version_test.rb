require "test_helper"

class DockerfileRubyVersionTest < ActiveSupport::TestCase
  test "Dockerfile ARG RUBY_VERSION matches .ruby-version" do
    ruby_version = Rails.root.join(".ruby-version").read.strip

    dockerfile = Rails.root.join("Dockerfile").read
    match = dockerfile.match(/^ARG RUBY_VERSION=(\S+)/)
    assert match, "Dockerfile is missing an ARG RUBY_VERSION= line"

    assert_equal ruby_version, match[1],
                 "Dockerfile ARG RUBY_VERSION (#{match[1]}) does not match .ruby-version (#{ruby_version})"
  end
end
