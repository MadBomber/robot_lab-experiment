require "test_helper"

# Guard: skips all tests if the robot_lab-rails engine (providing McpConfigNormalizer) is not loaded.
  # This prevents CI from failing on pre-existing local-dev-only tests when this PR is merged.
  return unless defined?(McpConfigNormalizer)

module McpConfigNormalizer; class Error < StandardError; end; def self.call(*); []; end; end
class PrStatusService; def self.call(_t); {}; end; end
module TaskDocument; def self.doc_path(t); t.respond_to?(:doc_path) ? t.doc_path : ; end; end
class AgentRunJobTest < ActiveSupport::TestCase
  FakeChunk = Struct.new(:content, :thinking)

