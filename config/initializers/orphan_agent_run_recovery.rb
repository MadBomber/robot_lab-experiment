# Agent runs are in-memory work (an ActiveJob executing a streaming Robot
# turn); a server/worker restart orphans any row still "running". Sweep those
# to "failed" at boot so the UI isn't stuck and the task is re-triggerable --
# mirrors Bottega's own orphan-run recovery on server start.
#
# Allowlisted to the actual server/worker process only: `rails server` defines
# Rails::Server, and the Solid Queue worker is invoked as bin/jobs. Everything
# else -- console, runner, rake/db tasks, the test suite -- is excluded by
# simply not matching either condition.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless defined?(Rails::Server) || $PROGRAM_NAME.end_with?("bin/jobs")

  begin
    AgentRun.where(status: "running").update_all(status: "failed")
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    # Database isn't ready yet (e.g. mid db:create/db:migrate bootstrapping) -- skip.
  end
end
