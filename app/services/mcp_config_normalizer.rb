# Reads a Claude Desktop / VS Code style MCP config file (JSON or YAML,
# with ERB interpolation) and normalizes it to the ruby_llm-mcp native shape:
#   { server_name => { transport_type: "stdio", command: ..., args: [...] } }
#
# Transport inference:
#   - presence of "command"  → stdio
#   - presence of "url"      → streamable
#   - anything else          → sse (skipped; not viable for background workers)
#
# Returns an empty hash when the config file does not exist, so callers
# can unconditionally invoke it and gracefully degrade.
class McpConfigNormalizer
  def self.load_and_normalize(path)
    return {} unless File.exist?(path)

    raw = ERB.new(File.read(path)).result(binding)

    config = if path.to_s.end_with?(".json")
      JSON.parse(raw)
    else
      YAML.safe_load(raw, permitted_classes: [Symbol]) || {}
    end

    server_map = (config["mcpServers"] || config.dig("mcp", "servers") || {})

    normalized = {}
    server_map.each do |name, spec|
      next unless spec.is_a?(Hash)

      if spec.key?("command")
        transport = "stdio"
      elsif spec["url"].present?
        transport = "streamable"
      else
        next   # skip SSE (not viable for background workers)
      end

      normalized[name] = spec.transform_keys(&:to_sym).merge(transport_type: transport)
    end

    normalized
  end
end
