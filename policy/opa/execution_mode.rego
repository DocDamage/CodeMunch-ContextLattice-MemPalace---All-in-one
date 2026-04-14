# execution_mode.rego
# OPA Rego policy for execution mode restrictions.
# Defines what safety levels and commands are allowed per execution mode.

package llmworkflow.execution_mode

import future.keywords.if
import future.keywords.in

# Valid execution modes
valid_modes := {"interactive", "ci", "watch", "heal-watch", "scheduled", "mcp-readonly", "mcp-mutating"}

# Default deny
default allow := false

# Allow if mode is valid and all constraints pass
allow if {
    input.mode in valid_modes
    not safety_violation
    not command_denied
}

# Safety level constraints per mode
safety_violation if {
    input.safetyLevel == "Destructive"
    non_interactive_mode[input.mode]
}

safety_violation if {
    input.safetyLevel == "Mutating"
    input.mode == "mcp-readonly"
}

safety_violation if {
    input.safetyLevel == "Networked"
    input.mode == "heal-watch"
}

# Command denials per mode
command_denied if {
    input.mode == "ci"
    input.command in {"restore", "prune", "delete", "switch-provider", "clean", "migrate"}
}

command_denied if {
    input.mode == "watch"
    input.command in {"migrate", "restore", "prune", "delete", "switch-provider", "clean"}
}

command_denied if {
    input.mode == "heal-watch"
    input.command in {"migrate", "restore", "prune", "delete", "sync", "index", "ingest"}
}

command_denied if {
    input.mode == "scheduled"
    input.command in {"restore", "prune", "delete", "migrate", "switch-provider", "clean"}
}

command_denied if {
    input.mode == "mcp-readonly"
    input.command in {"restore", "prune", "delete", "switch-provider", "migrate", "clean", "sync", "index", "ingest", "build"}
}

command_denied if {
    input.mode == "mcp-mutating"
    input.command in {"restore", "prune", "delete"}
}

# Helper sets
non_interactive_mode := {"ci", "watch", "heal-watch", "scheduled", "mcp-readonly", "mcp-mutating"}

# Explanations
explanation := "Operation allowed in current execution mode." if {
    allow
}

explanation := sprintf("Execution mode '%s' is not recognized.", [input.mode]) if {
    not input.mode in valid_modes
}

explanation := sprintf("Safety level '%s' is not allowed in mode '%s'.", [input.safetyLevel, input.mode]) if {
    safety_violation
    input.mode in valid_modes
}

explanation := sprintf("Command '%s' is denied in mode '%s'.", [input.command, input.mode]) if {
    command_denied
}
