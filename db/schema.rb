# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_18_062608) do
  create_table "agent_runs", force: :cascade do |t|
    t.string "agent_type", null: false
    t.boolean "cancel_requested", default: false, null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "status", default: "pending", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_agent_runs_on_conversation_id"
    t.index ["task_id", "status"], name: "index_agent_runs_on_task_id_and_status"
    t.index ["task_id"], name: "index_agent_runs_on_task_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "effort"
    t.string "model", null: false
    t.string "provider", null: false
    t.datetime "started_at", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_conversations_on_task_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "msg_type", null: false
    t.json "payload", default: {}, null: false
    t.integer "seq", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["conversation_id", "seq"], name: "index_messages_on_conversation_id_and_seq"
    t.index ["conversation_id", "uuid"], name: "index_messages_on_conversation_id_and_uuid", unique: true
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "repo_folder_path", null: false
    t.string "subproject_path"
    t.datetime "updated_at", null: false
    t.index ["repo_folder_path"], name: "index_projects_on_repo_folder_path", unique: true
  end

  create_table "tasks", force: :cascade do |t|
    t.string "blocked_reason"
    t.string "branch_name"
    t.datetime "created_at", null: false
    t.integer "no_progress_streak", default: 0, null: false
    t.text "pending_guidance"
    t.boolean "planning_complete", default: false, null: false
    t.boolean "pr_agent_complete", default: false, null: false
    t.string "progress_fingerprint"
    t.integer "project_id", null: false
    t.string "status", default: "pending", null: false
    t.string "task_kind", default: "fix", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.boolean "workflow_complete", default: false, null: false
    t.integer "workflow_run_count", default: 0, null: false
    t.string "worktree_path"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["status"], name: "index_tasks_on_status"
  end

  add_foreign_key "agent_runs", "conversations"
  add_foreign_key "agent_runs", "tasks"
  add_foreign_key "conversations", "tasks"
  add_foreign_key "messages", "conversations"
  add_foreign_key "tasks", "projects"
end
