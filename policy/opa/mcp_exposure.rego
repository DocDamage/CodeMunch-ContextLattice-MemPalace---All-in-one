# mcp_exposure.rego
# OPA Rego policy for MCP tool exposure.
# Defines rules for mutating vs read-only tools, review requirements,
# and workspace boundary constraints.

package llmworkflow.mcp_exposure

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow if the tool satisfies all exposure constraints
allow if {
    valid_tool_category
    review_requirement_satisfied
    workspace_bound_satisfied
    not exceeds_scope
}

# Valid tool categories
valid_tool_category if {
    input.toolCategory in {"read-only", "mutating"}
}

valid_tool_category if {
    not input.toolCategory
}

# Mutating tools require review before exposure
review_requirement_satisfied if {
    input.toolCategory != "mutating"
}

review_requirement_satisfied if {
    input.toolCategory == "mutating"
    input.requiresReview == true
    input.reviewApproved == true
}

# Workspace binding requirement
workspace_bound_satisfied if {
    input.workspaceBound == true
}

workspace_bound_satisfied if {
    not input.workspaceBound
}

# Scope limitation: mutating tools must not be exposed outside workspace
exceeds_scope if {
    input.toolCategory == "mutating"
    input.crossWorkspace == true
}

exceeds_scope if {
    input.toolCategory == "mutating"
    input.visibility in {"public-reference", "shared"}
}

# Explanations
explanation := "MCP tool exposure allowed." if {
    allow
}

explanation := "Invalid or missing tool category." if {
    not valid_tool_category
}

explanation := "Mutating MCP tools require review and approval before exposure." if {
    input.toolCategory == "mutating"
    not review_requirement_satisfied
}

explanation := "MCP tools must be workspace-bound." if {
    not workspace_bound_satisfied
}

explanation := "Mutating tools may not be exposed across workspace boundaries or to shared/public visibility." if {
    exceeds_scope
}
