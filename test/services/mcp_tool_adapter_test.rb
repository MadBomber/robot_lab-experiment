require "test_helper"
require "mcp"

class McpToolAdapterTest < ActiveSupport::TestCase
  def echo_tool
    RobotLab::Tool.create(name: "echo", description: "Echo the text back.",
                          parameters: { type: "object", properties: { text: { type: "string", description: "What to echo." } },
                                        required: ["text"] }) { |args| "echo: #{args[:text]}" }
  end

  def failing_tool
    RobotLab::Tool.create(name: "fail", description: "Always fails.") { |_args| raise "disk on fire" }
  end

  test "carries over the tool's name, description and input schema" do
    wrapped = McpToolAdapter.wrap(echo_tool)

    assert_equal "echo", wrapped.tool_name
    assert_equal "Echo the text back.", wrapped.description
    schema = wrapped.input_schema.to_h
    assert_equal "string", schema.dig(:properties, :text, :type)
    assert_equal ["text"], schema[:required]
  end

  test "calling it runs the tool and returns its result as text content" do
    response = McpToolAdapter.wrap(echo_tool).call(text: "hi", server_context: Object.new)

    assert_equal [{ type: "text", text: "echo: hi" }], response.content
    assert_not response.error?
  end

  test "a tool error comes back as text, as RobotLab::Tool#call reports it" do
    response = McpToolAdapter.wrap(failing_tool).call

    assert_match(/disk on fire/, response.content.first[:text])
  end

  test "a tool with no parameters gets an empty object schema" do
    assert_equal({ type: "object", properties: {} }, McpToolAdapter.input_schema(Struct.new(:to_json_schema).new({})))
  end

  test "serves through a real MCP server" do
    server = MCP::Server.new(name: "task", tools: [McpToolAdapter.wrap(echo_tool)])
    request = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "echo", arguments: { text: "yo" } } }

    reply = JSON.parse(server.handle_json(request.to_json))

    assert_equal "echo: yo", reply.dig("result", "content", 0, "text")
  end
end
