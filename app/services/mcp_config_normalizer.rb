require "erb"
require "json"
require "yaml"

# Reads a Claude Desktop / Cursor / ~/.mcp.json style MCP config file (JSON or
# YAML, with ERB interpolation for secrets) and normalizes it to the array of
# server specs RobotLab.build(mcp:) expects -- the config Hash shape
# RobotLab::MCP.build turns into a RubyLLM::MCP server:
#
#   [{ name: "playwright",
#      transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }]
#
# RobotLab owns the server lifecycle (register, connect on first use, attach
# tools per run, disconnect); this only translates the portable config format
# into its spec array.
#
# Path: defaults to config/mcp_servers.json, overridable with MCP_CONFIG_PATH
# (tilde-expanded, so MCP_CONFIG_PATH=~/.mcp.json reuses an existing home file).
#
# Transport: honors an explicit "type" (stdio/http/streamable-http), else
# infers from command (stdio) vs url (streamable-http). robot_lab runs MCP on
# ruby_llm's built-in client, which speaks only stdio and Streamable HTTP, so
# the legacy sse/ws types are rejected here with guidance.
#
# Returns [] when the file is absent. Raises McpConfigNormalizer::Error on a
# malformed file (array instead of object, missing command/url, unknown or
# unsupported type, or anything else RobotLab::MCP.define refuses)
# so misconfiguration fails loudly rather than silently loading no tools.
class McpConfigNormalizer
  class Error < StandardError; end

  DEFAULT_PATH = "config/mcp_servers.json".freeze

  def self.default_path
    ENV["MCP_CONFIG_PATH"].presence || Rails.root.join(DEFAULT_PATH).to_s
  end

  def self.call(path = default_path) = new(path).call

  def initialize(path)
    @path = File.expand_path(path.to_s) # expands ~ and relative paths
  end

  def call
    return [] unless File.exist?(@path)

    servers = parsed["mcpServers"]
    return [] if servers.nil?
    unless servers.is_a?(Hash)
      raise Error, "mcpServers must be an object keyed by server name, got #{servers.class}"
    end

    servers.filter_map { |name, spec| normalize(name, spec) }
  end

  private

  def parsed
    raw = ERB.new(File.read(@path)).result
    @path.end_with?(".json") ? JSON.parse(raw) : (YAML.safe_load(raw) || {})
  rescue JSON::ParserError, Psych::SyntaxError => e
    raise Error, "could not parse #{@path}: #{e.message}"
  end

  def normalize(name, spec)
    raise Error, "server '#{name}' must be an object, got #{spec.class}" unless spec.is_a?(Hash)

    validated({ name: name.to_s, transport: transport_for(name, spec) })
  end

  # Let robot_lab itself vet the spec (it builds the server class without
  # connecting), so anything it would refuse at RobotLab.build -- which would
  # fail the whole run -- surfaces here as a config error instead.
  def validated(server)
    RobotLab::MCP.define(server)
    server
  rescue RobotLab::MCPError, ArgumentError => e
    raise Error, "server '#{server[:name]}': #{e.message}"
  end

  def transport_for(name, spec)
    command, args, env, url, headers, type = spec.values_at("command", "args", "env", "url", "headers", "type")

    case (transport = resolved_type(name, type, command, url))
    when "stdio"
      raise Error, "server '#{name}': stdio transport requires a command" if command.blank?

      { type: "stdio", command:, args: Array(args), env: }.compact
    when "streamable-http"
      raise Error, "server '#{name}': #{transport} transport requires a url" if url.blank?

      { type: transport, url:, headers: }.compact
    end
  end

  # Explicit "type" wins; otherwise infer from command/url.
  def resolved_type(name, type, command, url)
    explicit = type.to_s.downcase.strip
    return normalize_type(name, explicit) if explicit.present?
    return "stdio" if command.present?
    return "streamable-http" if url.present?

    raise Error, "server '#{name}': cannot determine transport (no type, command, or url)"
  end

  def normalize_type(name, type)
    case type
    when "stdio" then "stdio"
    when "http", "streamable-http", "streamable", "streamable_http" then "streamable-http"
    when "sse", "ws", "websocket"
      raise Error, "server '#{name}': the '#{type}' transport is no longer supported -- " \
                   "point it at the server's Streamable HTTP endpoint (type \"http\") instead"
    else raise Error, "server '#{name}': unsupported transport type '#{type}'"
    end
  end
end
