import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { registerPoetryControllers } from "@poetry/controllers"
import { registerPoetryAgent } from "@poetry/agent"

eagerLoadControllersFrom("controllers", application)
registerPoetryControllers(application)
registerPoetryAgent(application)
