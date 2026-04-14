# interpack_transfer.rego
# OPA Rego policy for inter-pack transfers.
# Defines rules for source quarantine, promotion, and asset provenance.

package llmworkflow.interpack_transfer

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow if transfer satisfies all governance constraints
allow if {
    quarantine_check
    provenance_check
    promotion_check
    not blocked_destination
}

# Quarantine check: quarantined sources require promotion
quarantine_check if {
    input.sourceQuarantine != true
}

quarantine_check if {
    input.sourceQuarantine == true
    input.promoted == true
}

# Provenance verification
provenance_check if {
    input.provenanceVerified == true
}

provenance_check if {
    not input.provenanceVerified
    input.trustSource in {"core-runtime", "exemplar-pattern", "official"}
}

# Promotion check: promotion tier must match source safety
promotion_check if {
    not input.requiresPromotion
}

promotion_check if {
    input.requiresPromotion == true
    input.promotionTier in {"stable", "beta", "rc"}
}

# Blocked destinations
blocked_destination if {
    input.destinationPack in input.blockedDestinations
}

blocked_destination if {
    input.sourceSafetyLevel == "quarantined"
    input.destinationTier == "production"
}

# Explanations
explanation := "Inter-pack transfer allowed." if {
    allow
}

explanation := "Transfers from quarantined sources require promotion." if {
    not quarantine_check
}

explanation := "Asset provenance must be verified or sourced from a trusted origin." if {
    not provenance_check
}

explanation := "Promotion tier requirement not satisfied." if {
    not promotion_check
}

explanation := "Transfer to this destination is blocked by policy." if {
    blocked_destination
}
