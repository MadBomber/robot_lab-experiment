# Code coverage is opt-in (COVERAGE=1) so the normal parallel test run stays
# fast; bin/ci turns it on to enforce the 90% line gate. Must start before any
# application code is required so every file is tracked.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/test/"
    minimum_coverage line: 90
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Under coverage, run single-process for a simple, accurate measurement (no
    # cross-worker merging); otherwise parallelize across cores for speed.
    parallelize(workers: ENV["COVERAGE"] ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
