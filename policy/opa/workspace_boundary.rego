# workspace_boundary.rego
# OPA Rego policy for workspace and visibility boundaries.
# Defines rules for private, local-team, shared, and public-reference visibility.

package llmworkflow.workspace_boundary

import future.keywords.if
import future.keywords.in

# Valid visibility levels
valid_visibilities := {"private", "local-team", "shared", "public-reference"}

# Default deny
default allow := false

# Allow if visibility is valid and boundary constraints are satisfied
allow if {
    input.visibility in valid_visibilities
    not boundary_violation
    not unauthorized_cross_boundary
}

# Boundary violations
boundary_violation if {
    input.crossesBoundary == true
    count(input.allowedDestinations) == 0
}

boundary_violation if {
    input.visibility == "private"
    input.crossesBoundary == true
}

boundary_violation if {
    input.visibility == "local-team"
    input.crossesBoundary == true
    not team_destination
}

# Unauthorized cross-boundary operations
unauthorized_cross_boundary if {
    input.crossesBoundary == true
    input.authorizationLevel in {"guest", "anonymous"}
}

unauthorized_cross_boundary if {
    input.visibility == "public-reference"
    input.crossesBoundary == true
    input.includesSecrets == true
}

# Helper: destination is within the same team
team_destination if {
    input.destinationTeam == input.sourceTeam
}

team_destination if {
    input.destinationTeam in input.allowedTeams
}

# Explanations
explanation := "Workspace boundary constraints satisfied." if {
    allow
}

explanation := sprintf("Visibility '%s' is not recognized.", [input.visibility]) if {
    not input.visibility in valid_visibilities
}

explanation := "Cross-boundary operation requires at least one allowed destination." if {
    boundary_violation
    input.crossesBoundary == true
    count(input.allowedDestinations) == 0
}

explanation := "Private assets may not cross workspace boundaries." if {
    input.visibility == "private"
    input.crossesBoundary == true
}

explanation := "Local-team assets may only cross boundaries to authorized team destinations." if {
    input.visibility == "local-team"
    input.crossesBoundary == true
    not team_destination
}

explanation := "Cross-boundary operations require appropriate authorization level." if {
    unauthorized_cross_boundary
    input.authorizationLevel in {"guest", "anonymous"}
}

explanation := "Public-reference assets crossing boundaries must not include secrets." if {
    input.visibility == "public-reference"
    input.crossesBoundary == true
    input.includesSecrets == true
}
