require "test_helper"

class McpConfigNormalizerTest < ActiveSupport::TestCase
  def setup
    @tmpdir = Dir.mktmpdir("mcp_config_normalizer_test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # ---- config file does not exist ----

  test "returns empty hash when config file does not exist" do
    nonexistent_path = File.join(@tmpdir, "does_not_exist.json")
    refute File.exist?(nonexistent_path)

    result = McpConfigNormalizer.load_and_normalize(nonexistent_path)
    assert_equal({}, result)
  end

  # ---- JSON config (Claude Desktop format) ----

  test "converts mcpServers key to normalised shape with stdio transport" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcpServers": {
          "playwright": {
            "command": "npx",
            "args": ["-y", "@playwright/mcp@latest"]
          }
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_equal({
      command: "npx",
      args: ["-y", "@playwright/mcp@latest"],
      transport_type: "stdio"
    }, result["playwright"])
  end

  test "converts mcpServers key with url to streamable transport" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcpServers": {
          "http-server": {
            "url": "https://example.com/mcp"
          }
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_equal({
      url: "https://example.com/mcp",
      transport_type: "streamable"
    }, result["http-server"])
  end

  test "skips servers with null url (sse fallback)" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcpServers": {
          "sse-server": {
            "url": null
          }
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_empty result
  end

  test "handles multiple servers in one config" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcpServers": {
          "playwright": {
            "command": "npx",
            "args": ["-y", "@playwright/mcp@latest"]
          },
          "filesystem": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
          }
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_equal 2, result.size
    assert_equal "stdio", result.dig("playwright", :transport_type)
    assert_equal "stdio", result.dig("filesystem", :transport_type)
  end

  test "handles top-level mcp.servers alternate format" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcp": {
          "servers": {
            "alt-server": {
              "command": "node",
              "args": ["server.js"]
            }
          }
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_equal({
      command: "node",
      args: ["server.js"],
      transport_type: "stdio"
    }, result["alt-server"])
  end

  test "skips entries that are not hashes" do
    path = File.join(@tmpdir, "mcp_servers.json")
    File.write(path, <<~JSON)
      {
        "mcpServers": {
          "valid": {
            "command": "echo",
            "args": ["hello"]
          },
          "invalid_value": "just a string"
        }
      }
    JSON

    result = McpConfigNormalizer.load_and_normalize(path)

    assert_equal({
      command: "echo",
      args: ["hello"],
      transport_type: "stdio"
    }, result["valid"])
  end

  # ---- ERB interpolation ----

  test "ERB interpolation works when server values are env-templated" do
    path = File.join(@tmpdir, "mcp_servers.erb")
    erb_content = <<~'ERB'
      {
        "mcpServers": {
          "secretd": {
            "command": "<%= ENV.fetch("MCP_CMD", "npx") %>",
            "args": ["-y", "@playwright/mcp@latest"]
          }
        }
      }
    ERB
    File.write(path, erb_content)

    ENV["MCP_CMD"] = "custom-command"
    result = McpConfigNormalizer.load_and_normalize(path)
    assert_equal({ command: "custom-command", args: ["-y", "@playwright/mcp@latest"], transport_type: "stdio" }, result["secretd"])
  ensure
    ENV.delete("MCP_CMD")
  end
end
