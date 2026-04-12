# Task Board

> **Project**: {{PROJECT_NAME}}  
> **Sprint/Phase**: {{PHASE}}  
> **Last Updated**: {{LAST_UPDATED}}

---

## Quick Stats

| Status | Count |
|--------|-------|
| Not Started | {{COUNT_NOT_STARTED}} |
| In Progress | {{COUNT_IN_PROGRESS}} |
| Blocked | {{COUNT_BLOCKED}} |
| Done | {{COUNT_DONE}} |

---

## Kanban Board

### To Do
- [ ] {{TODO_1}} - @{{ASSIGN_1}} - {{ESTIMATE_1}}h
- [ ] {{TODO_2}} - @{{ASSIGN_2}} - {{ESTIMATE_2}}h
- [ ] {{TODO_3}} - @{{ASSIGN_3}} - {{ESTIMATE_3}}h

### In Progress
- [ ] {{WIP_1}} - @{{WIP_ASSIGN_1}} - started {{WIP_DATE_1}}
- [ ] {{WIP_2}} - @{{WIP_ASSIGN_2}} - started {{WIP_DATE_2}}

### Blocked
- [ ] {{BLOCKED_1}} - @{{BLOCK_ASSIGN_1}} - blocked by: {{BLOCKER_1}}
- [ ] {{BLOCKED_2}} - @{{BLOCK_ASSIGN_2}} - blocked by: {{BLOCKER_2}}

### Done
- [x] {{DONE_1}} - @{{DONE_ASSIGN_1}} - completed {{DONE_DATE_1}}
- [x] {{DONE_2}} - @{{DONE_ASSIGN_2}} - completed {{DONE_DATE_2}}

---

## Tasks by Category

### Code
| ID | Task | Assignee | Status | Priority | Est | Actual |
|----|------|----------|--------|----------|-----|--------|
| C1 | {{CODE_TASK_1}} | {{CODE_ASSIGN_1}} | {{CODE_STATUS_1}} | {{CODE_PRIO_1}} | {{CODE_EST_1}}h | {{CODE_ACT_1}}h |
| C2 | {{CODE_TASK_2}} | {{CODE_ASSIGN_2}} | {{CODE_STATUS_2}} | {{CODE_PRIO_2}} | {{CODE_EST_2}}h | {{CODE_ACT_2}}h |

### Art
| ID | Task | Assignee | Status | Priority | Est | Actual |
|----|------|----------|--------|----------|-----|--------|
| A1 | {{ART_TASK_1}} | {{ART_ASSIGN_1}} | {{ART_STATUS_1}} | {{ART_PRIO_1}} | {{ART_EST_1}}h | {{ART_ACT_1}}h |
| A2 | {{ART_TASK_2}} | {{ART_ASSIGN_2}} | {{ART_STATUS_2}} | {{ART_PRIO_2}} | {{ART_EST_2}}h | {{ART_ACT_2}}h |

### Audio
| ID | Task | Assignee | Status | Priority | Est | Actual |
|----|------|----------|--------|----------|-----|--------|
| S1 | {{AUDIO_TASK_1}} | {{AUDIO_ASSIGN_1}} | {{AUDIO_STATUS_1}} | {{AUDIO_PRIO_1}} | {{AUDIO_EST_1}}h | {{AUDIO_ACT_1}}h |
| S2 | {{AUDIO_TASK_2}} | {{AUDIO_ASSIGN_2}} | {{AUDIO_STATUS_2}} | {{AUDIO_PRIO_2}} | {{AUDIO_EST_2}}h | {{AUDIO_ACT_2}}h |

### Design
| ID | Task | Assignee | Status | Priority | Est | Actual |
|----|------|----------|--------|----------|-----|--------|
| D1 | {{DESIGN_TASK_1}} | {{DESIGN_ASSIGN_1}} | {{DESIGN_STATUS_1}} | {{DESIGN_PRIO_1}} | {{DESIGN_EST_1}}h | {{DESIGN_ACT_1}}h |
| D2 | {{DESIGN_TASK_2}} | {{DESIGN_ASSIGN_2}} | {{DESIGN_STATUS_2}} | {{DESIGN_PRIO_2}} | {{DESIGN_EST_2}}h | {{DESIGN_ACT_2}}h |

---

## Export Formats

### HacknPlan Import
Use this JSON for HacknPlan bulk import:

```json
{
  "tasks": [
    {
      "title": "{{TASK_TITLE_1}}",
      "description": "{{TASK_DESC_1}}",
      "category": "{{TASK_CAT_1}}",
      "assignee": "{{TASK_USER_1}}",
      "estimateHours": {{TASK_EST_1}},
      "priority": "{{TASK_PRIO_1}}"
    }
  ]
}
```

### Trello CSV Format
```csv
Name,Description,List,Labels,Members,Due Date
{{TASK_TITLE_1}},{{TASK_DESC_1}},{{TASK_LIST_1}},{{TASK_LABEL_1}},{{TASK_MEMBER_1}},{{TASK_DUE_1}}
{{TASK_TITLE_2}},{{TASK_DESC_2}},{{TASK_LIST_2}},{{TASK_LABEL_2}},{{TASK_MEMBER_2}},{{TASK_DUE_2}}
```

### GitHub Projects
Use these checklists in GitHub issues:

```markdown
## Sprint {{SPRINT_NUMBER}}

### P0 (Must Have)
- [ ] #{{ISSUE_1}} - {{ISSUE_TITLE_1}}
- [ ] #{{ISSUE_2}} - {{ISSUE_TITLE_2}}

### P1 (Should Have)
- [ ] #{{ISSUE_3}} - {{ISSUE_TITLE_3}}
- [ ] #{{ISSUE_4}} - {{ISSUE_TITLE_4}}

### P2 (Nice to Have)
- [ ] #{{ISSUE_5}} - {{ISSUE_TITLE_5}}
```

---

## Sprint Notes

### {{SPRINT_NAME}}
**Goal**: {{SPRINT_GOAL}}
**Dates**: {{SPRINT_START}} - {{SPRINT_END}}

#### Risks
- {{RISK_1}}
- {{RISK_2}}

#### Dependencies
- {{DEP_1}} blocks {{DEP_BLOCK_1}}
- {{DEP_2}} blocks {{DEP_BLOCK_2}}

---

*Format: Compatible with HacknPlan, Trello CSV, and GitHub Projects*
