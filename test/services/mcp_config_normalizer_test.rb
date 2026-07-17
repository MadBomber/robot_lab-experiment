require "test_helper"

class McpConfigNormalizerTest < ActiveSupport::TestCase
  def setup
    @tmpdir = Dir.mktmpdir("mcp_config_normalizer_test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write(name, body)
    path = File.join(@tmpdir, name)
    File.write(path, body)
    path
  end

  # ---- absent / empty ----

  test "returns [] when the config file does not exist" do
    assert_equal [], McpConfigNormalizer.call(File.join(@tmpdir, "nope.json"))
  end

  test "returns [] when mcpServers key is absent" do
    path = write("mcp_servers.json", '{"other": {}}')
    assert_equal [], McpConfigNormalizer.call(path)
  end

  # ---- stdio ----

  test "stdio transport is inferred from a command" do
    path = write("mcp_servers.json", <<~JSON)
      { "mcpServers": { "playwright": { "command": "npx", "args": ["-y", "@playwright/mcp@latest"] } } }
    JSON

    assert_equal(
      [{ name: "playwright", transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }],
      McpConfigNormalizer.call(path)
    )
  end

  test "stdio env is passed through" do
    path = write("mcp_servers.json", '{"mcpServers":{"gh":{"command":"docker","args":["run"],"env":{"TOKEN":"x"}}}}')
    spec = McpConfigNormalizer.call(path).first
    assert_equal({ type: "stdio", command: "docker", args: ["run"], env: { "TOKEN" => "x" } }, spec[:transport])
  end

  # ---- url / explicit type ----

  test "url with no type is treated as streamable-http" do
    path = write("mcp_servers.json", '{"mcpServers":{"api":{"url":"https://example.com/mcp"}}}')
    assert_equal(
      [{ name: "api", transport: { type: "streamable-http", url: "https://example.com/mcp" } }],
      McpConfigNormalizer.call(path)
    )
  end

  test "explicit sse type is honored (not collapsed to http)" do
    path = write("mcp_servers.json", '{"mcpServers":{"sentry":{"type":"sse","url":"https://mcp.sentry.dev/sse"}}}')
    assert_equal "sse", McpConfigNormalizer.call(path).first.dig(:transport, :type)
  end

  test "explicit http type maps to streamable-http" do
    path = write("mcp_servers.json", '{"mcpServers":{"api":{"type":"http","url":"https://x/mcp"}}}')
    assert_equal "streamable-http", McpConfigNormalizer.call(path).first.dig(:transport, :type)
  end

  # ---- multiple ----

  test "handles multiple servers with mixed transports" do
    path = write("mcp_servers.json", <<~JSON)
      { "mcpServers": {
        "playwright": { "command": "npx", "args": ["x"] },
        "remote":     { "type": "sse", "url": "https://s/sse" }
      } }
    JSON

    result = McpConfigNormalizer.call(path)
    assert_equal 2, result.size
    assert_equal "stdio", result.find { |s| s[:name] == "playwright" }.dig(:transport, :type)
    assert_equal "sse", result.find { |s| s[:name] == "remote" }.dig(:transport, :type)
  end

  # ---- loud failures on malformed config ----

  test "raises when mcpServers is an array instead of an object" do
    path = write("mcp_servers.json", '{"mcpServers":[{"command":"npx"}]}')
    error = assert_raises(McpConfigNormalizer::Error) { McpConfigNormalizer.call(path) }
    assert_match "must be an object", error.message
  end

  test "raises when a stdio server has no command" do
    path = write("mcp_servers.json", '{"mcpServers":{"bad":{"type":"stdio","args":["x"]}}}')
    error = assert_raises(McpConfigNormalizer::Error) { McpConfigNormalizer.call(path) }
    assert_match "requires a command", error.message
  end

  test "raises on an unsupported transport type" do
    path = write("mcp_servers.json", '{"mcpServers":{"weird":{"type":"carrier-pigeon","url":"x"}}}')
    error = assert_raises(McpConfigNormalizer::Error) { McpConfigNormalizer.call(path) }
    assert_match "unsupported transport type", error.message
  end

  test "raises on invalid JSON" do
    path = write("mcp_servers.json", "{ not json")
    assert_raises(McpConfigNormalizer::Error) { McpConfigNormalizer.call(path) }
  end

  # ---- ERB + path resolution ----

  test "ERB interpolates env vars in the config" do
    path = write("mcp_servers.erb", <<~ERB)
      { "mcpServers": { "s": { "command": "<%= ENV.fetch("MCP_CMD", "npx") %>", "args": [] } } }
    ERB
    ENV["MCP_CMD"] = "custom"
    assert_equal "custom", McpConfigNormalizer.call(path).first.dig(:transport, :command)
  ensure
    ENV.delete("MCP_CMD")
  end

  test "default_path honors MCP_CONFIG_PATH and expands a tilde" do
    ENV["MCP_CONFIG_PATH"] = "~/.mcp.json"
    assert_equal File.expand_path("~/.mcp.json"), File.expand_path(McpConfigNormalizer.default_path)
  ensure
    ENV.delete("MCP_CONFIG_PATH")
  end

  test "default_path falls back to config/mcp_servers.json" do
    ENV.delete("MCP_CONFIG_PATH")
    assert_equal Rails.root.join("config/mcp_servers.json").to_s, McpConfigNormalizer.default_path
  end
end
