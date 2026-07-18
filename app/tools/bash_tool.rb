require "open3"
require "timeout"

# Runs an arbitrary shell command within the working directory -- git, test
# runners, `gh`. RobotLab::ScriptTool (core gem) is a different thing: a
# factory for wrapping pre-existing executable *script files* (the AgentSkills
# pattern), not a general command runner, so it doesn't fit here.
class BashTool < CodingTool
  DEFAULT_TIMEOUT = 120

  description "Run a shell command in the working directory and return its combined stdout+stderr. Note: sandbox levels only apply to Ruby-level file reads; shell commands are confined by chdir but can access the filesystem through the OS."
  param :command, type: "string", desc: "The shell command to run."
  param :timeout, type: "integer", desc: "Max seconds to allow (default #{DEFAULT_TIMEOUT}).", required: false

  def execute(command:, timeout: DEFAULT_TIMEOUT)
    output = +""
    Open3.popen2e(command, chdir: cwd, pgroup: true) do |stdin, out, wait|
      stdin.close
      begin
        Timeout.timeout(timeout) { output << out.read }
      rescue Timeout::Error
        kill(wait.pid)
        return "#{output}\n[killed: exceeded #{timeout}s]"
      end
      return format_result(output, wait.value)
    end
  end

  private

  def format_result(output, status)
    status.success? ? output : "Error (exit #{status.exitstatus}):\n#{output}"
  end

  def kill(pid)
    Process.kill("-TERM", Process.getpgid(pid))
  rescue StandardError
    nil
  end
end
