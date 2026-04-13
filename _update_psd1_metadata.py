import re

with open('module/LLMWorkflow/LLMWorkflow.psd1', 'r', encoding='utf-8') as f:
    content = f.read()

# Update Description
new_desc = "All-in-one workflow platform for CodeMunch, ContextLattice, MemPalace, and 10 domain packs with 106 PowerShell modules. Includes observability backbone, policy externalization, document/game-asset ingestion, security baseline, durable execution, MCP governance, retrieval substrate, and v1.0 certification framework."
content = re.sub(r'Description\s*=\s*".*?"', f'Description = "{new_desc}"', content, flags=re.DOTALL)

# Update ReleaseNotes
new_notes = "v0.9.6: Post-0.9.6 strategic execution - observability backbone, policy externalization, document/game-asset ingestion, security baseline, durable execution, MCP governance, retrieval substrate, and v1.0 certification framework. Module contract reconciled with 352 exported functions after repairing 13 corrupted extraction parsers."
content = re.sub(r'ReleaseNotes\s*=\s*".*?"', f'ReleaseNotes = "{new_notes}"', content, flags=re.DOTALL)

with open('module/LLMWorkflow/LLMWorkflow.psd1', 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated psd1 metadata')
