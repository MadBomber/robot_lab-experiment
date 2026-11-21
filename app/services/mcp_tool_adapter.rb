require "mcp"

# Wraps one of the app's RobotLab tools as an MCP::Tool class for
# bin/task_mcp, so Claude Code calls the same tool object an lms or
# openrouter run would get -- no second implementation. The MCP name,
# description and input schema come straight from the tool. RobotLab::Tool#call
# already turns errors into a text result, so the response is always text.
module McpToolAdapter
  EMPTY_SCHEMA = { type: "object", properties: {} }.freeze

  module_function

  # @param tool [RobotLab::Tool]
  # @return [Class<MCP::Tool>]
  def wrap(tool)
    # The SDK passes server_context: to any block that takes **keywords; it
    # is the SDK's, not one of the tool's arguments.
    MCP::Tool.define(name: tool.name, description: tool.description, input_schema: input_schema(tool)) do |**args|
      MCP::Tool::Response.new([{ type: "text", text: tool.call(**args.except(:server_context)).to_s }])
    end
  end

  # The tool's JSON Schema without the keys MCP's InputSchema doesn't take.
  def input_schema(tool)
    schema = tool.to_json_schema[:parameters] || EMPTY_SCHEMA
    schema.slice(:type, :properties, :required).presence || EMPTY_SCHEMA
  end
end
