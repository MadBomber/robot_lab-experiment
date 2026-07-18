require "erb"
require "json"
require "yaml"

# Reads a Claude Desktop / Cursor / ~/.mcp.json style MCP config file (JSON or
# YAML, with ERB interpolation for secrets) and normalizes it to the array of
# server specs RobotLab.build(mcp_servers:) expects -- the RobotLab::MCP::Server
# shape:
#
#   [{ name: "playwright",
#      transport: { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] } }]
#
# RobotLab owns the client lifecycle (connect, tool injection, disconnect via
# Robot::MCPManagement); this only translates the portable config format into
# its spec array.
#
# Path: defaults to config/mcp_servers.json, overridable with MCP_CONFIG_PATH
# (tilde-expanded, so MCP_CONFIG_PATH=~/.mcp.json reuses an existing home file).
#
# Transport: honors an explicit "type" (stdio/sse/http/streamable-http/ws), else
# infers from command (stdio) vs url (streamable-http).
#
# Returns [] when the file is absent. Raises McpConfigNormalizer::Error on a
# malformed file (array instead of object, missing command/url, unknown type)
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

    servers = parsed.fetch("mcpServers", nil)
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

    { name: name.to_s, transport: transport_for(name, spec) }
  end

  def transport_for(name, spec)
    command, args, env, url, headers, type = spec.values_at("command", "args", "env", "url", "headers", "type")

    case (transport = resolved_type(name, type, command, url))
    when "stdio"
      raise Error, "server '#{name}': stdio transport requires a command" if command.blank?

      { type: "stdio", command:, args: Array(args), env: }.compact
    when "sse", "streamable-http"
      raise Error, "server '#{name}': #{transport} transport requires a url" if url.blank?

      { type: transport, url:, headers: }.compact
    when "ws"
      raise Error, "server '#{name}': ws transport requires a url" if url.blank?

      { type: "ws", url: }
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
    when "sse" then "sse"
    when "http", "streamable-http", "streamable", "streamable_http" then "streamable-http"
    when "ws", "websocket" then "ws"
    else raise Error, "server '#{name}': unsupported transport type '#{type}'"
    end
  end
end
